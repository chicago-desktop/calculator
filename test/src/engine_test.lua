-- The calculator: the engine and the window on the shell SDK.
--
-- What is checked is what makes a calculator lie silently: arithmetic that
-- counts not the way the buttons do; a failure that a digit can continue
-- from; a key drawn somewhere other than where it is pressed; a caption cut
-- to "..." at a cell width a terminal actually gives.
--
-- Every test file ends with `test.run_cases(define_tests)`. A file that puts
-- `test.describe` inside a `run` function and returns it is counted, printed
-- green in under a millisecond, and never executed: break a test on purpose
-- once and see it go red before trusting it.
local test = require("test")
local gfx = require("gfx")
local fs = require("fs")
local ui = require("ui")
local pixels = require("pixels")
local widgets = require("widgets")
local chrome = require("chrome")
local engine = require("engine")
local calc_window = require("window")

-- The pixel client of the 29x16 window: what the pixel theme's frame leaves.
local PIXEL_CLIENT = {w = 27, h = 14}
-- The keys of the standard view: Back, CE, C and four rows of six.
local KEYS = 3 + 4 * 6

-- Titles and ids of the menu bar items from the window tree.
local function menu_of(tree: any): (string, string, boolean)
    local titles, ids, disabled = {}, {}, false
    for _, child in ipairs(tree.children or {}) do
        if child.kind == "menu" then
            for _, entry in ipairs(child.entries) do
                titles[#titles + 1] = tostring(entry.title)
                for _, item in ipairs(entry.items or {}) do
                    if not item.separator then ids[#ids + 1] = tostring(item.id) end
                    if item.disabled then disabled = true end
                end
            end
        end
    end
    return table.concat(titles, " "), table.concat(ids, " "), disabled
end

-- The label with this text in the plan and its width: a sheet title cut down
-- to one cell shows as a single letter.
local function label_width(plan: any, text: string): any
    for _, item in ipairs(plan.items) do
        if item.node.kind == "label" and item.node.text == text then return item.rect.w end
    end
    return 0
end

-- Buttons named in cells do not share a cell: otherwise a click on the
-- border belongs to both at once, and whichever was found first wins.
local function assert_disjoint(buttons: any)
    for i = 1, #buttons do
        for j = i + 1, #buttons do
            local a, b = buttons[i], buttons[j]
            local rows = a.row <= b.bottom_row and b.row <= a.bottom_row
            local cols = a.from <= b.to and b.from <= a.to
            test.is_false(rows and cols, a.id .. " and " .. b.id .. " share a cell")
        end
    end
end

-- The window's tree laid out in the pixel client.
local function pixel_plan(state: any): any
    local tree = calc_window.definition.view(state, {width = PIXEL_CLIENT.w, height = PIXEL_CLIENT.h, native = true})
    return ui.plan(tree, PIXEL_CLIENT.w, PIXEL_CLIENT.h, ui.interaction())
end

local function define_tests()
    test.describe("Calculator", function()
        test.it("counts like the buttons, not like an expression", function()
            local state = engine.new()
            for _, id in ipairs({"2", "add", "3", "mul", "4", "eq"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "20.", "2 + 3 × 4 on a desk calculator is twenty")
            test.is_true(state.fresh)
        end)

        test.it("the display shows a whole number with a dot, a fraction without a second one", function()
            local state = engine.new()
            test.eq(engine.display(state), "0.")
            for _, id in ipairs({"1", "dot", "5", "dot"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "1.5")
            state = engine.press(state, "neg")
            test.eq(engine.display(state), "-1.5")
        end)

        test.it("division by zero is a phrase, and after it only a reset works", function()
            local state = engine.new()
            for _, id in ipairs({"8", "div", "0", "eq"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "Cannot divide by zero")
            state = engine.press(state, "5")
            test.eq(engine.display(state), "Cannot divide by zero", "a digit after the refusal does not count")
            state = engine.press(state, "ce")
            test.eq(engine.display(state), "0.")
            state = engine.press(state, "inv")
            test.eq(engine.display(state), "Cannot divide by zero")
            state = engine.press(state, "c")
            test.eq(engine.display(state), "0.")
        end)

        test.it("memory survives the C reset and is shown on the display", function()
            local state = engine.new()
            for _, id in ipairs({"4", "2", "ms", "c"}) do state = engine.press(state, id) end
            test.eq(state.memory, 42)
            state = engine.press(state, "mplus")
            test.eq(state.memory, 42, "M+ of zero does not change the memory")
            state = engine.press(state, "mr")
            test.eq(engine.display(state), "42.")
            state = engine.press(state, "mc")
            test.is_nil(state.memory)
        end)

        test.it("Back, CE, square root and percent behave as in the original", function()
            local state = engine.new()
            for _, id in ipairs({"1", "2", "3", "back"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "12.")
            state = engine.press(state, "back"); state = engine.press(state, "back")
            test.eq(engine.display(state), "0.", "erased to the end is zero, not empty")
            for _, id in ipairs({"8", "1", "sqrt"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "9.")
            for _, id in ipairs({"5", "0", "add", "1", "0", "pct"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "5.", "10 % of the accumulated 50 is five")
            state = engine.press(state, "eq")
            test.eq(engine.display(state), "55.")
            for _, id in ipairs({"7", "add", "ce", "3", "eq"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "10.", "CE erases the input, but not the operation")
        end)

        test.it("keys arrive at the same buttons as the mouse", function()
            test.eq(engine.key({key_type = "runes", key = "7"}), "7")
            test.eq(engine.key({key_type = "runes", key = "*"}), "mul")
            test.eq(engine.key({key_type = "runes", key = ","}), "dot", "a comma is a decimal point too")
            test.eq(engine.key({key_type = "enter", key = "enter"}), "eq")
            test.eq(engine.key({key_type = "backspace"}), "back")
            test.eq(engine.key({key_type = "esc"}), "c")
            test.eq(engine.key({key_type = "delete"}), "ce")
            test.eq(engine.key({key_type = "runes", key = "C"}), "c", "the capital letter also clears")
            test.eq(engine.key({key_type = "runes", key = "\209\129"}), "c", "Cyrillic es (the same key on a Russian layout) clears too")
            test.eq(engine.key({key_type = "runes", key = "\208\161"}), "c", "and its capital")
            test.is_nil(engine.key({key_type = "runes", key = "q"}))
            test.is_nil(engine.key("not an event"))
        end)

        test.it("SDK buttons stand in the original's grid, share no cells and fit in the window", function()
            local state = calc_window.definition.init(nil, {})
            local plan = pixel_plan(state)
            local buttons = {}
            for _, item in ipairs(plan.items) do
                if item.node.kind == "button" then
                    buttons[#buttons + 1] = {id = item.node.id, from = item.rect.x, to = item.rect.x + item.rect.w - 1,
                        row = item.rect.y, bottom_row = item.rect.y + item.rect.h - 1}
                end
            end
            test.eq(#buttons, KEYS)
            assert_disjoint(buttons)
            for _, button in ipairs(buttons) do
                test.is_true(button.to <= PIXEL_CLIENT.w and button.bottom_row <= PIXEL_CLIENT.h, button.id .. " beyond the edge")
            end
            test.eq(ui.hit(plan, 7, 6).node.id, "7")
            test.eq(ui.hit(plan, 26, 13).node.id, "eq")
            test.eq(ui.hit(plan, 2, 12).node.id, "mplus")
            test.eq(ui.hit(plan, 6, 6).node.kind, "label", "the gap between the memory and the keys is empty")
            test.eq(ui.hit(plan, 10, 2).node.kind, "field", "the display is not a button")
        end)

        test.it("a click and a key count the same, the highlight goes out by its own timer", function()
            -- The context records the one-shot timers the window asks for.
            local timers: any = {}
            local context: any = {after = function(_, tag) timers[#timers + 1] = tag end, close = function() end}
            local state = calc_window.definition.init(nil, context)
            calc_window.definition.update(state, {type = "activate", id = "7"}, context)
            calc_window.definition.update(state, {type = "key", key_type = "runes", key = "*"}, context)
            calc_window.definition.update(state, {type = "activate", id = "6"}, context)
            calc_window.definition.update(state, {type = "key", key_type = "enter", key = "enter"}, context)
            test.eq(engine.display(state.calc), "42.")
            test.eq(state.calc.pressed, "eq", "the last button is highlighted")
            test.eq(#timers, 4, "every press starts a highlight timer")
            local plan = pixel_plan(state)
            test.is_true(plan.by_id.eq.node.pressed == true)
            test.eq(calc_window.definition.update(state, {type = "timer", tag = timers[3]}, context), false,
                "the timer of an earlier press leaves the later highlight on")
            test.eq(state.calc.pressed, "eq")
            test.eq(calc_window.definition.update(state, {type = "timer", tag = timers[4]}, context), true)
            test.is_nil(state.calc.pressed, "the timer turns the highlight off")
        end)

        -- The owner's screenshot (2026-09-11): MC, MR, MS, M+ and sqrt showed
        -- "..." in pixels. At a 10 px cell the old 10 px padding still fitted
        -- them; at 9 px it cut sqrt, at 8 px also the memory keys — which
        -- matches the screenshot. Every key is drawn here the way the SDK
        -- renderer draws it — its cells minus `inset` on each side, the
        -- shell's bold Liberation Sans 13 — at cell widths terminals actually
        -- give, and the caption `pixels.button` hands to the raster must be
        -- the key's whole caption.
        test.it("draws every key caption whole in pixels at the shell's font and 8 to 10 px cells", function()
            local files = assert(fs.get("app:system_fonts"))
            local bold = assert(gfx.font(assert(files:readfile("LiberationSans-Bold.ttf")), {size = 13, smooth = true}))
            local state = calc_window.definition.init(nil, {})
            local plan = pixel_plan(state)
            -- Captions are collected in a table field, not an upvalue: go-lua
            -- splits upvalues after an error caught by pcall.
            local seen: any = {list = {}}
            local stub: any = {
                rect = function() end,
                set = function() end,
                text = function(_, _, _, caption) seen.list[#seen.list + 1] = caption; return 0 end,
            }
            local checked, cut = 0, {}
            for _, width in ipairs({8, 9, 10}) do
                local cell = {w = width, h = 20}
                for _, item in ipairs(plan.items) do
                    local node: any = item.node
                    if node.kind == "button" then
                        local pad = node.inset or 0
                        local bw = item.rect.w * cell.w - pad * 2
                        seen.list = {}
                        pixels.button(stub, 1, 1, bw, item.rect.h * cell.h - pad * 2,
                            {label = node.text, font = bold}, cell)
                        if seen.list[1] ~= node.text then
                            cut[#cut + 1] = string.format("%s at %d px cell: %q in a %d px key, caption %d px",
                                tostring(node.id), width, tostring(seen.list[1]), bw, bold:measure(node.text))
                        end
                        checked = checked + 1
                    end
                end
            end
            test.eq(checked, 3 * KEYS, "every key is checked at every cell width")
            test.eq(table.concat(cut, "; "), "", "every caption is drawn whole")
            -- 16 px leave 12 px of room: too little for "s…", enough for "s".
            test.eq(pixels.caption(bold, "sqrt", 16), "s", "a key too narrow for the dots is cut, not left with an ellipsis")
        end)

        -- In cells the client of the 29x16 window is what the cell theme's
        -- insets leave, 25x11 — not the 27x14 of pixels. Every key must fit
        -- there, share no cell, and hold its caption between two bevels.
        test.it("fits the cell client and shows every caption whole between bevels", function()
            local inset = chrome.window_insets({})
            local width, height = 29 - inset.left - inset.right, 16 - inset.top - inset.bottom
            test.eq(width .. "x" .. height, "25x11", "the cell client of the calculator window")
            local state = calc_window.definition.init(nil, {})
            local plan = ui.plan(calc_window.definition.view(state, {width = width, height = height, native = false}),
                width, height, ui.interaction())
            local buttons = {}
            for _, item in ipairs(plan.items) do
                local node: any = item.node
                if node.kind == "button" then
                    local rect = item.rect
                    local name = "key " .. tostring(node.id)
                    buttons[#buttons + 1] = {id = node.id, from = rect.x, to = rect.x + rect.w - 1,
                        row = rect.y, bottom_row = rect.y + rect.h - 1}
                    test.is_true(rect.x + rect.w - 1 <= width and rect.y + rect.h - 1 <= height, name .. " is inside the client")
                    test.is_true(widgets.cells(node.text) + 2 <= rect.w, name .. " has room for its caption and both bevels")
                    local shown = tostring(widgets.button(node.text, {room = rect.w})):gsub("\27%[[%d;:]*m", "")
                    test.is_true(shown:find(node.text, 1, true) ~= nil, name .. " shows its caption whole: " .. shown)
                    test.eq(widgets.cells(shown), rect.w, name .. " fills exactly its cells, like its column")
                end
            end
            test.eq(#buttons, KEYS, "every key is laid out")
            assert_disjoint(buttons)
            test.eq((tostring(widgets.button("MC", {room = 4})):gsub("\27%[[%d;:]*m", "")):gsub("[^%w]", ""), "MC")
        end)

        test.it("the menu has only \"About\": the sheet opens, keys do not count under it", function()
            local context: any = {after = function() end, close = function() end}
            local state = calc_window.definition.init(nil, context)
            local titles, ids, disabled = menu_of(calc_window.definition.view(state,
                {width = PIXEL_CLIENT.w, height = PIXEL_CLIENT.h, native = true}))
            test.eq(titles, "Help", "No Edit — the window has no clipboard; no View — there is only one view")
            test.eq(ids, "about")
            test.is_false(disabled, "there are no permanently disabled items")

            calc_window.definition.update(state, {type = "activate", id = "about", menu = "bar"}, context)
            test.is_true(state.about, "\"About\" opens the sheet")
            local plan = pixel_plan(state)
            test.not_nil(plan.by_id.about_ok, "the sheet has \"OK\"")
            local ok = plan.by_id.about_ok.rect
            test.is_true(ok.x + ok.w - 1 <= PIXEL_CLIENT.w and ok.y + ok.h - 1 <= PIXEL_CLIENT.h, "\"OK\" is inside the window")
            test.is_true(label_width(plan, "Calculator") >= #"Calculator", "the sheet title is visible whole")

            test.eq(calc_window.definition.update(state, {type = "key", key_type = "runes", key = "7"}, context), false)
            test.eq(engine.display(state.calc), "0.", "a digit under the sheet is not typed")
            calc_window.definition.update(state, {type = "key", key_type = "esc", key = "esc"}, context)
            test.is_false(state.about, "Esc closes the sheet")
            calc_window.definition.update(state, {type = "activate", id = "about", menu = "bar"}, context)
            calc_window.definition.update(state, {type = "activate", id = "about_ok"}, context)
            test.is_false(state.about, "\"OK\" closes the sheet")
            test.eq(engine.display(state.calc), "0.", "neither \"about\" nor \"about_ok\" went into the calculator")
        end)
    end)

    test.describe("Calculator display of large integers", function()
        -- go-lua formats an integer under %g as Go's bad-verb text, and an integer
        -- reaches the engine's "%.12g" whenever it is too large for the %d branch
        -- (|x| >= 1e15). Operands are read with tonumber, so a product of two
        -- typed integers is an integer.
        test.it("shows a product past 1e15 as a number, not as %!g(lua.LInteger=…)", function()
            local state = engine.new()
            for _, id in ipairs({"9", "9", "9", "9", "9", "9", "9", "9", "9", "mul",
                "9", "9", "9", "9", "9", "9", "9", "9", "9", "eq"}) do
                state = engine.press(state, id)
            end
            test.eq(engine.display(state), "9.99999998e+17", "999999999 × 999999999")
            test.eq(engine.format(1000000000000000), "1e+15", "an integer literal past the %d branch")
        end)

        test.it("control: an ordinary integer result keeps the %d path", function()
            local state = engine.new()
            for _, id in ipairs({"2", "add", "2", "eq"}) do state = engine.press(state, id) end
            test.eq(engine.display(state), "4.", "2 + 2 =")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
