-- The calculator's process: the registry entry the Start menu reads, the
-- module's own calculator icon found at both sizes, the process running the
-- engine, and a shot (test/shots/calculator.png) drawn by the shell's own
-- renderer — evidence for the eye, next to the checks for the machine.
local test = require("test")
local gfx = require("gfx")
local fs = require("fs")
local registry = require("registry")
local app = require("app")
local ui = require("ui")
local render = require("render")
local rasters = require("rasters")
local images = require("images")
local engine = require("engine")
local window = require("window")

local definition = window.definition

-- The pixel client of the 29x16 window, and the cell of the stand this was
-- measured on.
local CLIENT = {w = 27, h = 14}
local CELL = {w = 10, h = 20}

-- The shell's face and bold fonts, as bytes from the harness's font folder:
-- the keys' captions are bold, the display is not.
local function fonts(): any
    local files = assert(fs.get("app:system_fonts"))
    local face = assert(gfx.font(assert(files:readfile("LiberationSans-Regular.ttf")), {size = 13, smooth = true}))
    local bold = assert(gfx.font(assert(files:readfile("LiberationSans-Bold.ttf")), {size = 13, smooth = true}))
    return {face = face, bold = bold}
end

local function define_tests()
    test.describe("Calculator window", function()
        test.it("is a fixed-size window on the shell SDK in Programs, with its own calculator icon at both sizes", function()
            local entry = assert(registry.get("windows.calculator:window"))
            local meta: any = entry.meta
            test.eq(table.concat({meta.type, meta.title, meta.group, meta.image, meta.window_type,
                meta.pixel_render, meta.pixel_state}, "|"),
                "tui_desktop.window|Calculator|Programs|windows.calculator:images/calculator|app|windows.shell.sdk:render|windows.calculator:window")
            test.eq(tostring(meta.width) .. "x" .. tostring(meta.height), "29x16", "the outer size in cells")
            test.is_true(meta.resizable == false, "a fixed size: the frame gets no \"maximize\"")
            for _, size in ipairs({32, 16}) do
                local picture, why = images.get(meta.image, size)
                test.not_nil(picture, "calculator@" .. tostring(size) .. ": " .. tostring(why))
            end
        end)

        test.it("runs the engine: a fresh state, the tree with the display, a press counted, Esc clears", function()
            local timers: any = {}
            local context: any = app.context({width = CLIENT.w, height = CLIENT.h, native = true})
            context.after = function(_, tag) timers[#timers + 1] = tag end
            local model = definition.init("", context)
            test.eq(engine.display(model.calc), "0.")
            test.is_false(model.about)
            local tree = definition.view(model, context)
            test.is_nil(ui.problem(tree), "the tree lays out")
            test.eq(tree.children[1].id, "bar", "the menu bar on the first row")
            test.is_true(definition.update(model, {type = "activate", id = "5"}, context) ~= false, "a press redraws")
            test.eq(engine.display(model.calc), "5.")
            test.eq(#timers, 1, "the press started its highlight timer")
            -- Esc is the calculator's C, not a close: `app.dispatch` runs one
            -- action the way the loop does, and the window stays open.
            test.is_nil(definition.close_on_escape)
            app.dispatch(definition, model, context, {type = "key", key_type = "esc"})
            test.eq(engine.display(model.calc), "0.", "Esc clears the calculator")
            test.is_false(context.closing, "and does not close the window")
        end)

        test.it("draws 12 x 3.5 = into test/shots/calculator.png", function()
            local context: any = app.context({width = CLIENT.w, height = CLIENT.h, native = true,
                cell_w = CELL.w, cell_h = CELL.h})
            context.after = function() end
            local model = definition.init("", context)
            for _, id in ipairs({"1", "2", "mul", "3", "dot", "5", "eq"}) do
                definition.update(model, {type = "activate", id = id}, context)
            end
            test.eq(engine.display(model.calc), "42.")
            local tree = definition.view(model, context)
            test.is_nil(ui.problem(tree))
            local store = rasters.store()
            store.begin()
            local placed = assert(render.placement({id = "calculator", state_revision = 1, content_state = {sdk = 1, revision = 1,
                ui = tree, interaction = context.interaction}}, {x = 1, y = 1, cols = CLIENT.w, rows = CLIENT.h},
                CELL, fonts(), store))
            assert(assert(fs.get("app:shots")):writefile("calculator.png", assert(placed.raster:encode("png"))))
            test.eq(placed.cols .. "x" .. placed.rows, tostring(CLIENT.w) .. "x" .. tostring(CLIENT.h))
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
