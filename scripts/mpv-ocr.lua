-- mpv-ocr.lua
-- MPV script: OCR bottom 30% of screen and copy to clipboard
-- Works on Wayland (grim/wl-copy) and X11 (maim/xclip)

local utils = require 'mp.utils'

-- CONFIG
local config = {
    ocr_cmd = "tesseract",      -- Tesseract OCR command
    preprocess = true,          -- Preprocess for better OCR
    interval = 0.5,             -- Auto OCR interval in seconds
    psm = "6",                  -- Tesseract Page Segmentation Mode
    hotkey = "Ctrl+o",          -- Hotkey for manual OCR
}

local last_text = ""

-- Helper to run shell commands
local function run_command(cmd, input)
    local proc = utils.subprocess({
        args = cmd,
        cancellable = false,
        capture_stdout = true,
        capture_stderr = true,
        stdin_data = input or nil,
    })
    return proc.stdout or ""
end

-- Detect Wayland vs X11
local wayland = utils.get_env("WAYLAND_DISPLAY") ~= nil
local clipboard_cmd = wayland and "wl-copy" or "xclip"
local clipboard_args = wayland and {} or {"-selection", "clipboard"}

-- Capture bottom 30% of the video
local function capture_region()
    local vo = mp.get_property_native("osd-width"), mp.get_property_native("osd-height")
    local w = vo[1] or 1920
    local h = vo[2] or 1080
    local y = math.floor(h * 0.7)
    local height = h - y
    local region = string.format("0,%d %dx%d", y, w, height)
    local output_file = "/tmp/mpv_dialog.png"

    local cmd
    if wayland then
        cmd = {"grim", "-g", region, output_file}
    else
        cmd = {"maim", "-g", region, output_file}
    end
    utils.subprocess({args = cmd, cancellable = false})
    return output_file
end

-- Preprocess for OCR
local function preprocess_image(img)
    if not config.preprocess then return img end
    local out = "/tmp/mpv_dialog_proc.png"
    utils.subprocess({args = {"convert", img, "-colorspace", "Gray", "-threshold", "60%", out}})
    return out
end

-- OCR function
local function ocr_image(img)
    local proc_img = preprocess_image(img)
    local text = run_command({config.ocr_cmd, proc_img, "stdout", "--psm", config.psm})
    return text:gsub("%s+$","") -- remove trailing whitespace
end

-- Copy text to clipboard
local function copy_clipboard(text)
    utils.subprocess({args = (wayland and {"wl-copy"} or {"xclip", "-selection", "clipboard"}), stdin_data = text})
end

-- Main function
local function do_ocr()
    local img = capture_region()
    local text = ocr_image(img)
    if text ~= "" and text ~= last_text then
        last_text = text
        copy_clipboard(text)
        mp.osd_message("OCR: " .. text, 3)
    end
end

-- Auto OCR timer
local timer = mp.add_periodic_timer(config.interval, do_ocr)

-- Manual OCR hotkey
mp.add_key_binding(config.hotkey, "manual-ocr", do_ocr)
