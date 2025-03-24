local screenWidth, screenHeight = love.window.getDesktopDimensions()
local font_size
local cell_width
local cell_height
local screen_width
local screen_height
local elapsedTime = 0 
local backup_timer = 10
local page_size

local block_line_start = -1
local block_line_end = -1

local doc = {}
local cursor_y = 1
local cursor_position = 1
local active_type = "SCENE"
local scroll_offset = 0
local font

local key_hold = { up = false, down = false, left = false, right = false, backspace = false, delete = false, lctrl = false}
local key_timer = { up = 0, down = 0, left = 0, right = 0, backspace = 0, delete = 0 }
local key_repeat_delay = 0.5
local key_repeat_speed = 0.05

local bottom_margin = 2
local scroll_margin
local scroll_threshold

local menu_active = 0
local menu_index = 1
local menu_options = {
    { "New Script", "Save Script", "Load Script", "Export to Textfile", "Exit Program", "Return to Editor" }, { }, { }, { }
}
local show_confirmation = false
local confirmation_action = nil
local has_confirmed = false 

local file_open = ""
local new_filename = ""
local simple_message = ""

local show_linenumbers = false 
local indent_width = 10
local sceneList = {}
local currentSceneName = ""
local currentSceneNumber = 1 

local backup_directory
local export_directory
local max_backups
local settings
local show_pages 

local max_linewidth_action 
local max_linewidth_dialogue 
local max_linewidth_scene
local max_linewidth_character
local max_linewidth_parenthesis

local dirPath = love.filesystem.getSourceBaseDirectory()
local function_active = "NONE"

local searchword = ""
local jump_to_location = ""
local jump_marker = 1

local color_background = {1, 1, 1}
local color_text = {0, 0, 0}
local color_scene = {0, 0, 1}
local color_blockmarking = {1, 0, 0}
local color_search = {0, 1, 0}
local color_grey = {0.5, 0.5, 0.5}

function love.load()
    settings = loadSettings()
    
    font_size = settings.fontSize 
    font = love.graphics.newFont(settings.fontPath, font_size)
    love.graphics.setFont(font)

    cell_width = font:getWidth("W") 
    cell_height = font:getHeight() 

    screen_width = math.floor(screenWidth/cell_width)
    screen_height = math.floor(screenHeight/cell_height)
    scroll_margin = math.floor(screen_height/2) - 1
    scroll_threshold = screen_height - scroll_margin
    page_size = settings.pageSize
    
    love.window.setMode(screen_width * cell_width, screen_height * cell_height, { fullscreen = settings.fullscreen, resizable = settings.resizable })
    love.mouse.setVisible(false)
    love.graphics.setBackgroundColor(0, 0, 0)
    
    show_linenumbers = settings.show_linenumbers
    indent_width = settings.indent_width
    backup_timer = settings.backup_timer
    backup_directory = settings.backup_directory
    max_backups = settings.max_backups
    export_directory = settings.export_directory
    max_linewidth_action = settings.max_linewidth_action 
    max_linewidth_dialogue = settings.max_linewidth_dialogue
    max_linewidth_scene = settings.max_linewidth_scene
    max_linewidth_character = settings.max_linewidth_character
    max_linewidth_parenthesis = settings.max_linewidth_parenthesis 
    color_text = convertColorFromStringToTable(settings.color_text)
    color_background = convertColorFromStringToTable(settings.color_background)
    color_scene = convertColorFromStringToTable(settings.color_scene)
    color_blockmarking = convertColorFromStringToTable(settings.color_blockmarking)
    color_search = convertColorFromStringToTable(settings.color_search)
    color_grey = convertColorFromStringToTable(settings.color_grey) 

    show_pages = settings.show_pages

    menu_active = 1

    add_line("SCENE", "")
end

function convertColorFromStringToTable(colorString)
    local colorTable = {}
    for value in colorString:gmatch("[^,]+") do
        table.insert(colorTable, tonumber(value:match("^%s*(.-)%s*$"))) -- Trim spaces and convert to number
    end
    return colorTable
end

function love.update(dt)
    if menu_active == 0 and is_empty_or_whitespace(file_open) then
        menu_active = 1 
    end

    if doc then
        if doc.content then 
            if cursor_position > #doc.content then 
                cursor_position = #doc.content 
            end
        end
    end

    local _line = current_line() 

    if _line then 
        if cursor_position > #_line.content + 1 then 
            cursor_position = #_line.content + 1
        end
    end

    if menu_active == 0 and not is_empty_or_whitespace(file_open) then  
        elapsedTime = elapsedTime + dt
        if elapsedTime >= backup_timer then
            createBackup(file_open)
            elapsedTime = 0 
        end
    end

    for key, is_held in pairs(key_hold) do
        if is_held then
            key_timer[key] = key_timer[key] + dt
            if key_timer[key] >= key_repeat_delay then
                key_timer[key] = key_timer[key] - key_repeat_speed

                if key == "up" then
                    do_upscroll()                    
                elseif key == "down" then
                    do_downscroll()
                elseif key == "left" then
                    do_leftscroll()
                elseif key == "right" then
                    do_rightscroll()
                elseif key == "backspace" then
                    do_backspace()
                elseif key == "delete" then
                    do_delete()
                end
                active_type = current_line().type
                update_display_text()
                handle_scrolling()
            end
        end
    end

    if dt < 1/20 then
        love.timer.sleep(1/20 - dt)
    end  
end

function do_upscroll()
    cursor_y = math.max(1, cursor_y - 1)
    local line = current_line()
    if cursor_position > #line.content + 1 then
        cursor_position = #line.content + 1
    end
    currentSceneName = getClosestScene(cursor_y) 
    simple_message = ""
end

function do_downscroll()
    cursor_y = math.min(#doc, cursor_y + 1)
    local line = current_line()
    if cursor_position > #line.content + 1 then
        cursor_position = #line.content + 1
    end
    currentSceneName = getClosestScene(cursor_y) 
    simple_message = ""
end

function get_previous_word_position(line, position)
    local content = line.content
    local i = position - 1

    while i > 0 and content:sub(i-1, i-1):match("%S") ~= nil do
        i = i - 1
    end

    if i < 1 then
        i = 1
    end

    return i
end

function copy_lines()
    
    if block_line_start > 0 and block_line_end > 0 then
        local clipboard_text = ""
        for i = block_line_start, block_line_end do
            clipboard_text = clipboard_text .. doc[i].type .. "|" .. doc[i].content .. "\n"
        end
        love.system.setClipboardText(clipboard_text)
    else
        simple_message = "Error: No lines selected for copying."
    end
end

function cut_lines()
    
    if block_line_start > 0 and block_line_end > 0 then
        local cursor_y_original = block_line_start
        local clipboard_text = ""
        for i = block_line_start, block_line_end do
            clipboard_text = clipboard_text .. doc[i].type .. "|" .. doc[i].content .. "\n"
        end
        love.system.setClipboardText(clipboard_text)

        for i = block_line_end, block_line_start, -1 do
            if i <= jump_marker then 
                jump_marker = jump_marker - 1   
            end  

            table.remove(doc, i)
        end

        if #doc == 0 then
            table.insert(doc, { type = active_type, content = "", cursor_position = 1 })
            print("Failsafe: Added an empty line as the document was empty.")
        end

        cursor_y = cursor_y_original
        scroll_offset = math.max(0, math.min(#doc - screen_height + bottom_margin, cursor_y))
    else
        simple_message = "Error: No lines selected for cutting."
    end
end

function paste_lines()
    local clipboard_text = love.system.getClipboardText()

    if not clipboard_text or clipboard_text == "" then
        simple_message = "Error: Clipboard is empty or nil"
        return
    end

    local lines = {}
    for line in clipboard_text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    for _, line in ipairs(lines) do
        if line.content then 
            line.content = sanitizeUTF8(line.content)
        end

        if line:find("|") then
            -- Parse the line with type and content
            local type_prefix, content = line:match("^([A-Z]+)|?(.*)$")
            if type_prefix then
                content = sanitizeUTF8(content) or ""
                if content == "" then
                    -- Add an empty line if there's nothing after the pipe
                    local empty_line_entry = { type = type_prefix, content = "", cursor_position = 1 }
                    if cursor_y <= jump_marker then 
                        jump_marker = jump_marker + 1   
                    end  
                    table.insert(doc, cursor_y, empty_line_entry)
                    cursor_y = cursor_y + 1
                else
                    -- Get the maximum line length for this type
                    local max_length = get_max_length_of_linetype(type_prefix)
                    
                    -- Split the content into words
                    local words = {}
                    for word in content:gmatch("%S+") do
                        table.insert(words, word)
                    end
        
                    add_words_with_line_breaks(words, max_length, type_prefix)
                end
            else
                simple_message = "Warning: Invalid line format with '|': " .. line
            end
        else
            local current_line = doc[cursor_y]
            if current_line then
                -- local before_cursor = current_line.content:sub(1, cursor_position - 1)
                -- local after_cursor = current_line.content:sub(cursor_position)
                -- local new_line = before_cursor .. sanitizeUTF8(line) .. after_cursor
                -- current_line.content = new_line
                -- cursor_position = cursor_position + #line
                local content = sanitizeUTF8(line) 
                -- Get the maximum line length for this type
                local max_length = get_max_length_of_linetype(current_line.type)
                
                -- Split the content into words
                local words = {}
                for word in content:gmatch("%S+") do
                    table.insert(words, word)
                end

                add_words_with_line_breaks(words, max_length, current_line.type)

                
            else
                simple_message = "Error: Current line is nil"
            end
        end
        centerScroll()
    end
end

function add_words_with_line_breaks(words, max_length, type_prefix)
    -- Split the content into multiple lines based on max_length, keeping word boundaries
    local current_line = ""
    for _, word in ipairs(words) do
        -- Check if adding the word would exceed max_length
        if #current_line + #word + 1 <= max_length then
            -- If it fits, add the word to the current line
            if #current_line > 0 then
                current_line = current_line .. " " .. word
            else
                current_line = word
            end
        else
            -- If it doesn't fit, add the current line to the document and start a new one
            local new_line_entry = { type = type_prefix, content = current_line, cursor_position = 1 }
            if cursor_y <= jump_marker then 
                jump_marker = jump_marker + 1   
            end  
            table.insert(doc, cursor_y, new_line_entry)
            cursor_y = cursor_y + 1

            -- Start the new line with the current word
            current_line = word
        end
    end

    -- Insert the last line if there's any remaining content
    if #current_line > 0 then
        local new_line_entry = { type = type_prefix, content = current_line, cursor_position = 1 }
        if cursor_y <= jump_marker then 
            jump_marker = jump_marker + 1   
        end  
        table.insert(doc, cursor_y, new_line_entry)
        cursor_y = cursor_y + 1
    end
    
end

function get_next_word_position(line, position)
    local content = line.content
    local i = position + 1

    while i <= #content and content:sub(i, i):match("%S") ~= nil do
        i = i + 1
    end

    while i <= #content and content:sub(i, i):match("%s") ~= nil do
        i = i + 1
    end

    if i > #content + 1 then
        i = #content + 1
    end

    return i
end

function do_leftscroll()
    
    local line = current_line()
    if key_hold.lctrl then  
        local prev_position = get_previous_word_position(line, cursor_position)
        if prev_position < cursor_position then
            cursor_position = prev_position
        elseif cursor_y > 1 then
            cursor_y = cursor_y - 1
            local prev_line = current_line()
            if prev_line then
                cursor_position = #prev_line.content + 1
            end
        end
    else
        if cursor_position > 1 then
            cursor_position = cursor_position - 1
        elseif cursor_y > 1 then
            cursor_y = cursor_y - 1
            local prev_line = current_line()
            if prev_line then
                cursor_position = #prev_line.content + 1
            end
        end
    end
end

function do_rightscroll()
    
    local line = current_line()
    if key_hold.lctrl then
        local next_position = get_next_word_position(line, cursor_position)
        if next_position > cursor_position then
            cursor_position = next_position
        elseif cursor_y < #doc then
            cursor_y = cursor_y + 1
            local next_line = current_line()
            if next_line then
                cursor_position = 1
            end
        end
    else
        if cursor_position <= #line.content then
            cursor_position = cursor_position + 1
        elseif cursor_y < #doc then
            cursor_y = cursor_y + 1
            local next_line = current_line()
            if next_line then
                cursor_position = 1
            end
        end
    end
end

function extract_first_word(str)
    local space_pos = str:find(" ")

    if space_pos then
        return str:sub(1, space_pos)
    else
        return str
    end
end

function append_word_if_fit(A, B, max_length)
    local first_word = extract_first_word(B)
    local fit = false 

    if #A + #first_word <= max_length then
        A = A .. first_word

        B = B:sub(#first_word + 1) 

        fit = true 
    end

    return A, B, fit, first_word
end

function get_max_length_of_linetype(linetype) 
    if linetype == "SCENE" then 
        return max_linewidth_scene
    elseif linetype == "ACTION" then
        return max_linewidth_action
    elseif linetype == "DIALOGUE" then
        return max_linewidth_dialogue
    elseif linetype == "CHARACTER" then
        return max_linewidth_character 
    elseif linetype == "PARENTHESIS" then 
        return max_linewidth_parenthesis 
    end
    
    return screen_width
end

function do_backspace()
    if delete_block() then
        return
    end

    local line = current_line()

    if #line.content == 0 and cursor_y > 1 then
        if cursor_y <= jump_marker then 
            jump_marker = jump_marker - 1   
        end  
        table.remove(doc, cursor_y) 
        cursor_y = cursor_y - 1 
        local prev_line = current_line()

        if prev_line then
            local old_loc = #prev_line.content + 1
            prev_line.content = prev_line.content .. line.content
            cursor_position = old_loc
        end
    elseif cursor_position == 1 and cursor_y > 1 then
        local prev_line = doc[cursor_y - 1] 

        if prev_line then
            if is_empty_or_whitespace(prev_line.content) then 
                if cursor_y <= jump_marker then 
                    jump_marker = jump_marker - 1   
                end  
                table.remove(doc, cursor_y - 1)  
                cursor_y = cursor_y - 1     
            else 

                -- At the moment, it currently just moves the remaining content of a single line up a line, but I would like it to do it for all the subsequent lines of the same type, sp until it hits a line of another type 
                local word_fits = true 
                local original_y = cursor_y 
                local new_cursor_position = #prev_line.content+1

                while word_fits do 
                    A, B, fit, first_word = append_word_if_fit(prev_line.content, line.content, get_max_length_of_linetype(prev_line.type))
                    prev_line.content = A 
                    line.content = B

                    if fit then
                        cursor_position = new_cursor_position
                        cursor_y = original_y - 1
                    else 
                        word_fits = false 
                        prev_line.content = prev_line.content:sub(1, -2)
                    end 
                    
                    if #line.content == 0 or is_empty_or_whitespace(line.content) then
                        word_fits = false
                        if cursor_y <= jump_marker then 
                            jump_marker = jump_marker - 1   
                        end  
                        table.remove(doc, cursor_y+1) 
                    end
                end 
                -- For each subsequent line, if it has space left, it should try to pull content from the next line, but only if it is of the same type as itself. It should also make sure that it only pulls up full words and not pieces of a word. It should keep in mind the document length (#doc) as to not access illegal data 
            end
        end
    elseif cursor_position > 1 then
        if key_hold.lctrl then
            if #line.content > 0 and cursor_position > 1 then
                local start_of_word = get_previous_word_position(line, cursor_position)

                if start_of_word < cursor_position then
                    local start_part = line.content:sub(1, start_of_word - 1)  -- Part before the word
                    local end_part = line.content:sub(cursor_position)    -- Part after the word
                    line.content = start_part .. end_part
                    cursor_position = start_of_word  -- Move the cursor back to the start of the word
                end
            end
        else
            local start = line.content:sub(1, cursor_position - 2)
            local end_part = line.content:sub(cursor_position)
            line.content = start .. end_part
            cursor_position = cursor_position - 1
        end
    end

    update_display_text()  -- Update the display after the backspace action

    if jump_marker > #doc then
        jump_marker = #doc
    elseif jump_marker < 1 then 
        jump_marker = 1 
    end
end

function do_delete()
    if delete_block() then
        return
    end

    local line = current_line()

    if key_hold.lctrl then
        if #line.content > 0 and cursor_position <= #line.content then
            local end_of_word = get_next_word_position(line, cursor_position)

            if end_of_word > cursor_position then
                local start_part = line.content:sub(1, cursor_position - 1)  -- Part before the word
                local end_part = line.content:sub(end_of_word)    -- Part after the word
                line.content = start_part .. end_part
            end
        end
    else
        if cursor_position <= #line.content then
            local start = line.content:sub(1, cursor_position - 1)
            local end_part = line.content:sub(cursor_position + 1)
            line.content = start .. end_part
        end
    end
end

function delete_block() 
    local blockDeleted = false

    if block_line_start ~= -1 and block_line_end ~= -1 then
        local cursor_y_to_jump = block_line_start

        for i = block_line_end, block_line_start, -1 do
            if i <= jump_marker then 
                jump_marker = jump_marker - 1   
            end  
            table.remove(doc, i) 
        end
        
        block_line_start = -1
        block_line_end = -1
        
        blockDeleted = true
        cursor_y = cursor_y_to_jump 
        cursor_position = 1 
        centerScroll() 
    end

    return blockDeleted 
end

function add_line(type, content)
    local new_line = { type = type, content = content or "", cursor_position = 1, visual_position = 0 } -- Add cursor_position
    table.insert(doc, new_line)
end

function insert_line_at_cursor(type)
    local current_line = doc[cursor_y]

    if current_line then
        local before_cursor = current_line.content:sub(1, cursor_position - 1)
        local after_cursor = current_line.content:sub(cursor_position)

        current_line.content = before_cursor

        local new_line = { type = type, content = after_cursor, cursor_position = 1, visual_position = 0 }

        table.insert(doc, cursor_y + 1, new_line)

        if cursor_y <= jump_marker then 
            jump_marker = jump_marker + 1   
        end  

        cursor_position = 1
    else
        print("Error: No current line found.")
    end

    update_display_text()
end

function current_line()
    if cursor_y >= 1 and cursor_y <= #doc then
        return doc[cursor_y]
    end
    return nil
end

function update_display_text()
    local y_offset = 0 -- Vertical position for the lines

    for i, line in ipairs(doc) do
        line.visual_position = y_offset
        y_offset = y_offset + 1
    end
end

function handle_scrolling()
    local total_lines = #doc
    local cursor_position_on_screen = cursor_y - scroll_offset  -- Position of the cursor relative to the screen

    if cursor_position_on_screen >= scroll_threshold then
        scroll_down()
    elseif cursor_position_on_screen <= scroll_margin then
        scroll_up()
    end

    cursor_y = math.max(1, math.min(cursor_y, total_lines))
end

function scroll_up()    
    scroll_offset = math.max(0, scroll_offset - 1)
end

function scroll_down()    
    scroll_offset = math.min(#doc - screen_height + bottom_margin, scroll_offset + 1)
end

function do_page_up()
    for i = 1, page_size do
        do_upscroll()
        handle_scrolling()
    end
    currentSceneName = getClosestScene(cursor_y) 
    update_display_text()
end

function do_page_down()
    local doc_height = #doc
    for i = 1, page_size do
        do_downscroll()
        handle_scrolling()
    end
    currentSceneName = getClosestScene(cursor_y) 
    update_display_text()
end

function love.textinput(text)
    if menu_active == 0 and not has_confirmed then
        if function_active == "NONE" then 
            local line = current_line()

            if line and not string.find(text, "%|") and not string.find(text, "`") then
                local start = line.content:sub(1, cursor_position - 1)
                local end_part = line.content:sub(cursor_position)

                local indent = 0
                if line.type == "CHARACTER" then
                    indent = 3 * indent_width
                elseif line.type == "PARENTHESIS" then
                    indent = 2 * indent_width
                elseif line.type == "SCENE" then
                    indent = 0
                end

                local max_width = screen_width - 6 - indent

                max_width = get_max_length_of_linetype(line.type)

                line.content = start .. text .. end_part
                cursor_position = cursor_position + 1

                if #line.content > max_width then
                    -- Handle moving the current word to a new line
                    local last_space = string.find(line.content:sub(1, max_width), "%s[^%s]*$")
                    local word_to_move = ""
                    local inside_moving_word = false

                    if last_space then
                        word_to_move = line.content:sub(last_space + 1):gsub("^%s+", "") -- Trim leading spaces
                        line.content = line.content:sub(1, last_space - 1) -- Remove the word but keep the space
                    else
                        -- No spaces, move the overflowed text
                        word_to_move = line.content:sub(max_width + 1)
                        line.content = line.content:sub(1, max_width)
                    end
                    
                    if last_space ~= nil then 
                        if cursor_position > last_space then 
                            inside_moving_word = true
                        end
                    end
                    
                    local createNewLine = true 

                    if cursor_y + 1 < #doc and not inside_moving_word then 
                        local next_line
                        next_line = doc[cursor_y+1]
                        
                        if #next_line.content + 1 + #word_to_move < get_max_length_of_linetype(next_line.type) then
                            next_line.content = word_to_move .. " " ..  next_line.content
                            createNewLine = false
                        end 
                    end

                    if inside_moving_word then
                        createNewLine = true 
                    end
 
                    if createNewLine then 
                        -- Create a new line with the moved word
                        local new_line = { type = line.type, content = word_to_move }
                        table.insert(doc, cursor_y + 1, new_line)
                    -- end 
                    -- -- Update cursor position and line index
                    -- if cursor_position > max_width or inside_moving_word then 
                        if cursor_position > max_width then 
                            cursor_y = cursor_y + 1
                            cursor_position = #word_to_move + 1
                        end
                    end
                else
                    -- Ensure cursor stays within current line if no wrapping occurred
                    cursor_position = cursor_position
                end

                update_display_text()
            end
        elseif function_active == "SEARCH" then
            if #searchword < 40 then  
                simple_message = ""
                searchword = searchword .. text:gsub("([%[%]%^%$%(%)%.%*%+%-%?])", "") 
            end
        elseif function_active == "JUMP" then
            if text:match("[0123456789]") then
                if #jump_to_location < 5 then
                    jump_to_location = jump_to_location .. text
                end
            end
        end
                
    end 
    
    if menu_active == 3 and not show_confirmation then
        if #new_filename < 99 then 
            new_filename = new_filename .. text
        end
    end

    currentSceneName = getClosestScene(cursor_y)
end


-- Recursive function to wrap lines
function wrap_line_recursively(line_index, max_width)
    local line = doc[line_index]
    if not line then return end

    if #line.content > max_width then
        local content = line.content
        local last_space = find_last_space(content, max_width) or max_width
        local overflow = content:sub(last_space + 1)

        -- Fit the current line within max width
        line.content = content:sub(1, last_space)

        -- Check if the next line exists and is of the same type
        if not doc[line_index + 1] or doc[line_index + 1].type ~= line.type then
            -- Insert a new empty line of the same type
            table.insert(doc, line_index + 1, { type = line.type, content = "" })
        end

        -- Add overflow to the next line and check it recursively
        local next_line = doc[line_index + 1]
        next_line.content = overflow .. next_line.content
        wrap_line_recursively(line_index + 1, max_width)
    end
end

function find_last_space(content, max_width)
    -- Start at max_width and move backward until a space is found
    for i = max_width, 1, -1 do
        if content:sub(i, i):match("%s") then
            return i
        end
    end
    return nil -- Return nil if no space is found
end

local types = {"SCENE", "ACTION", "DIALOGUE", "PARENTHESIS", "CHARACTER"}

function love.keypressed(key)
    if key == "escape" then
        if menu_active == 0 then 
            menu_active = 1 
        elseif menu_active == 1 and not is_empty_or_whitespace(file_open) then
            menu_active = 0
        elseif menu_active == 2 then
            menu_active = 1 
        elseif menu_active == 3 then
            menu_active = 1
            new_filename = ""
            simple_message = ""
        elseif menu_active == 4 then 
            menu_active = 0
        end
        menu_index = 1 
        show_confirmation = false
    elseif menu_active == 3 and not show_confirmation then 
        if key == "return" then
            local files = getScreenplayFiles()

            local file_exists = false
            for _, filename in ipairs(files) do
                if filename == new_filename .. ".screenplay" then
                    file_exists = true
                    break
                end
            end

            if is_empty_or_whitespace(new_filename) then
                simple_message = "Please enter a filename, filenames cannot be empty."
                return
            end

            if file_exists then
                simple_message = "This file already exists."
                return 
            end

            file_open = new_filename .. ".screenplay"
            handle_menu_selection()
            simple_message = ""

        elseif key == "backspace" then
            if #new_filename > 0 then 
                new_filename = new_filename:sub(1, #new_filename-1)
            end
        end
    elseif menu_active ~= 0 and not show_confirmation then
        if key == "up" then
            menu_index = (menu_index - 2) % #menu_options[menu_active] + 1
        elseif key == "down" then
            menu_index = menu_index % #menu_options[menu_active] + 1
        elseif key == "return" or key == "space" then
            handle_menu_selection()
        end
    elseif show_confirmation then
        if key == "y" then
            confirmation_action()
            menu_active = 0
            show_confirmation = false
            has_confirmed = true
        elseif key == "n" then
            show_confirmation = false
        end
    elseif function_active == "NONE" then 
        local line = current_line()
        if not line then return end

        if key_hold[key] ~= nil then
            key_hold[key] = true
            key_timer[key] = 0 -- Reset the timer for this key
        end

        if key == "backspace" then
            do_backspace()
            currentSceneName = getClosestScene(cursor_y) 
            update_display_text()
        elseif key == "delete" then
            do_delete()
            currentSceneName = getClosestScene(cursor_y) 
            update_display_text()
        elseif key == "return" then
            if cursor_position > #line.content then 
                if active_type == "CHARACTER" then
                    active_type = "DIALOGUE"
                elseif active_type == "SCENE" then 
                    active_type = "ACTION"
                end
            end

            insert_line_at_cursor(active_type)
            cursor_y = cursor_y + 1
            currentSceneName = getClosestScene(cursor_y) 
            update_display_text()

        elseif key == "up" then
            if love.keyboard.isDown("lctrl") then 
                go_to_previous_line_of_different_type()
                currentSceneName = getClosestScene(cursor_y) 
            else
                do_upscroll()
            end
            update_display_text()
        elseif key == "down" then
            if love.keyboard.isDown("lctrl") then
                go_to_next_line_of_different_type()
                currentSceneName = getClosestScene(cursor_y) 
            else
                do_downscroll()
            end
            update_display_text()
        elseif key == "left" then
            do_leftscroll()
            update_display_text()
        elseif key == "right" then
            do_rightscroll()
            update_display_text()
        elseif key == "pagedown" then
            do_page_down()
            update_display_text()
        elseif key == "pageup" then
            do_page_up()
            update_display_text()
        elseif key == "home" then
            cursor_position = 1
            update_display_text()
        elseif key == "end" then
            cursor_position = #line.content + 1
            update_display_text()
        elseif (key == "f" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f2" then
            function_active = "SEARCH"
            simple_message = ""
        elseif (key == "j" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f3" then
            function_active = "JUMP"
            simple_message = ""
        elseif key == "`" then
            sceneList = getSceneList()
        
            if #sceneList == 0 then
                return
            end
        
            menu_index = currentSceneNumber  -- Set the closest scene index
            menu_active = 4
        
            local sceneTitles = {}
        
            for index, scene in ipairs(sceneList) do
		    -- Get the line number of the next scene
		    local next_scene_line_number = sceneList[index + 1] and sceneList[index + 1].line_number or #doc + 1

		    -- Calculate the number of pages the scene spans
		    local start_page = math.floor(1 + scene.line_number / page_size)
		    local end_page = math.floor(1 + (next_scene_line_number - 1) / page_size)

		    -- Calculate the number of lines in the current scene
		    local num_lines_in_scene = next_scene_line_number - scene.line_number - 1

		    -- Add the scene's title with the number of pages and lines it spans
		    table.insert(sceneTitles, index .. ": " .. string.upper(scene.content) .. " (Pages: " .. (end_page - start_page + 1) .. ", Lines: " .. num_lines_in_scene .. ")")
		end

        
            menu_options[4] = sceneTitles
        elseif key == "f9" then
            show_pages = not show_pages
            settings.show_pages = show_pages
            saveSettings(settings)
        elseif key == "f10" then
            indent_width = indent_width - 1
            if indent_width < 1 then 
                indent_width = 30
            end
            settings.indent_width = indent_width
            saveSettings(settings)
        elseif key == "f11" then
            indent_width = indent_width + 1
            if indent_width > 30 then
                indent_width = 1
            end
            settings.indent_width = indent_width
            saveSettings(settings)
        elseif key == "f12" then
            show_linenumbers = not show_linenumbers 
            settings.show_linenumbers = show_linenumbers
            saveSettings(settings)
        elseif love.keyboard.isDown("lctrl") and key == "lalt" then
            block_line_start = cursor_y
            if block_line_end < block_line_start then
                block_line_end = block_line_start
            end
            if block_line_start == -1 then block_line_start = cursor_y end
            if block_line_end == -1 then block_line_end = cursor_y end
        elseif love.keyboard.isDown("lctrl") and key == "ralt" then
            block_line_end = cursor_y
            if block_line_start > block_line_end then
                block_line_start = block_line_end
            end
            if block_line_start == -1 then block_line_start = cursor_y end
            if block_line_end == -1 then block_line_end = cursor_y end
        elseif love.keyboard.isDown("lctrl") and key == "c" then
            if block_line_end > -1 and block_line_start > -1 then
                copy_lines()
                update_display_text()
                block_line_start = -1
                block_line_end = -1
            end
        elseif love.keyboard.isDown("lctrl") and key == "x" then
            if block_line_end > -1 and block_line_start > -1 then
                cut_lines()
                update_display_text()
                block_line_start = -1
                block_line_end = -1
            end
        elseif love.keyboard.isDown("lctrl") and key == "v" then
            paste_lines()
            update_display_text()
            block_line_start = -1
            block_line_end = -1
        elseif love.keyboard.isDown("lctrl") and key == "m" then
            if jump_marker == cursor_y then
                jump_marker = -1 
            else
                jump_marker = cursor_y
            end
        elseif key == "lalt" or key == "ralt" then
            block_line_start = -1
            block_line_end = -1
        end

        if key == "tab" then
            if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
                local current_index = 1
                for i, t in ipairs(types) do
                    if t == active_type then
                        current_index = i
                        break
                    end
                end
                active_type = types[(current_index - 2) % #types + 1]
            else
                local current_index = 1
                for i, t in ipairs(types) do
                    if t == active_type then
                        current_index = i
                        break
                    end
                end
                active_type = types[(current_index % #types) + 1]
            end
            line.type = active_type
            currentSceneName = getClosestScene(cursor_y) 
        end
        handle_scrolling()
        active_type = current_line().type
    elseif function_active == "JUMP" then
        if (key == "j" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f3" or key == "left" or key == "right" or key == "down" or key == "up" then 
            function_active = "NONE"
            simple_message = ""
        end

        if (key == "m" and jump_marker ~= -1) then 
            if jump_marker <= #doc then 
                cursor_y = jump_marker
                centerScroll()
            end
        end

        if (key == "f" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f2" then 
            function_active = "SEARCH"
            simple_message = ""
        end
        
        local jump_to_location_int = tonumber(jump_to_location) 
        
        if key == "return" then
            if jump_to_location_int ~= nil then 
                if  jump_to_location_int >= 1 and jump_to_location_int < #doc then
                    cursor_y = jump_to_location_int
                else 
                    if jump_to_location_int < 1 then
                        cursor_y = 1 
                    elseif jump_to_location_int > #doc then
                        cursor_y = #doc 
                    end
                end
                
                cursor_position = 1 
                centerScroll()
                jump_to_location = ""
            end
        end

        if key == "backspace" then
            if #jump_to_location > 0 then
                jump_to_location = jump_to_location:sub(1, #jump_to_location - 1) 
            end
        end


    elseif function_active == "SEARCH" then 
        if (key == "f" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f2" or key == "left" or key == "right" or key == "down" or key == "up" then
            searchword = ""
            function_active = "NONE"
            simple_message = ""
        end

        if (key == "j" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))) or key == "f3" then 
            function_active = "JUMP"
            simple_message = ""
        end

        if key == "backspace" then
            if #searchword > 0 then
                searchword = searchword:sub(1, #searchword - 1) 
            end
            simple_message = ""
        end
        if key == "return" and not is_empty_or_whitespace(searchword) then
            local search_lower = searchword:lower()
            local start_index = cursor_y
            local wrapped = false
            
            -- Search from cursor_y to the end of the document
            for i = cursor_y+1, #doc do
                if doc[i].content:lower():find(search_lower) then
                    cursor_y = i
                    local start_index, end_index = doc[i].content:lower():find(search_lower)
                    cursor_position = start_index or 1
                    centerScroll()
                    return
                end
            end
            
            for i = 1, cursor_y do
                if doc[i].content:lower():find(search_lower) then
                    cursor_y = i
                    local start_index, end_index = doc[i].content:lower():find(search_lower)
                    cursor_position = start_index or 1
                    centerScroll()
                    return
                end
            end
            
            simple_message = "No match found for: " .. searchword
        end
    end
end

function love.keyreleased(key)
    if key_hold[key] ~= nil then
        key_hold[key] = false
        key_timer[key] = 0 -- Reset the timer to avoid lingering effects
    end
    if key == "y" then
        has_confirmed = false 
    end
end

function handle_menu_selection()
    if menu_active == 2 then 
        confirmation_action = function() 
            file_open = menu_options[2][menu_index] 
            load_script() 
        end
        show_confirmation = true
    elseif menu_active == 4 then
        menu_active = 0 
        cursor_position = 1
        cursor_y = sceneList[menu_index].line_number
        centerScroll()
        currentSceneName = getClosestScene(cursor_y) 
        currentSceneNumber = getSceneIndexBySceneLine(cursor_y)
    else 
        local selected_option = menu_options[1][menu_index]
        if selected_option == "New Script" then
            if menu_active == 1 then
                menu_active = 3
                new_filename = "" 
                cursor_position = 1
                return
            end
            confirmation_action = new_script
        elseif selected_option == "Save Script" then
            confirmation_action = save_script
        elseif selected_option == "Load Script" then
            if menu_active == 1 then 
                menu_active = 2
                menu_index = 1
                menu_options[2] = getScreenplayFiles()
                if #menu_options[2] == 0 then
                    menu_active = 1
                end
                return
            end
        elseif selected_option == "Export to Textfile" then
            if not is_empty_or_whitespace(file_open) then 
                exportToTXT(file_open)
                simple_message = file_open .. " has been exported."
                menu_active = 0 
                menu_index = 1
            end
            return
        elseif selected_option == "Exit Program" then
            confirmation_action = function() love.event.quit() end
        elseif selected_option == "Return to Editor" then
            menu_active = 0
            return
        end
        show_confirmation = true
    end
end

function getScreenplayFiles()
    local screenplayFiles = {}
    local command

    if package.config:sub(1, 1) == "\\" then
        -- Windows system
        command = 'dir "' .. dirPath .. '" /b' -- /b gives a bare list of file names
    else
        -- Unix-based system (Linux, macOS)
        command = 'ls -1 "' .. dirPath .. '"'
    end

    local handle = io.popen(command)
    if handle then
        local result = handle:read("*a")
        handle:close()

        for file in result:gmatch("[^\r\n]+") do
            if file:match("%.screenplay$") then
                table.insert(screenplayFiles, file)
            end
        end
    else
        print("Error: Unable to list directory contents.")
    end

    return screenplayFiles
end

function getSceneList()
    local scenes = {}
    local scene_index = 1  -- Initialize scene index

    for line_number, line in ipairs(doc) do
        if line.type == "SCENE" and not is_empty_or_whitespace(line.content) then
            local lineToAdd = { line_number = line_number, content = line.content, scene_index = scene_index }
            table.insert(scenes, lineToAdd)
            scene_index = scene_index + 1  -- Increment scene index for the next scene
        end
    end

    return scenes
end

function new_script()
    doc = {}
    add_line("SCENE", "")
    sceneList = {}
    cursor_y = 1
    cursor_position = 1
    scroll_offset = math.max(0, math.min(#doc - screen_height + bottom_margin, 0))
    currentSceneName = ""
end

function save_script()
    save_to_app_dir(file_open)
end

function load_script()
    load_from_app_dir(file_open)
    cursor_position = 1
    --scroll_offset = math.max(0, math.min(#doc - screen_height + bottom_margin, 0))
    menu_active = 0
    menu_index = 1
    currentSceneName = getClosestScene(cursor_y) 
end

function love.draw()
    love.graphics.setBackgroundColor(color_background)
    if menu_active == 1 or menu_active == 2 or menu_active == 4 then
        draw_menu(menu_options[menu_active])
        if show_confirmation then
            draw_confirmation()
        end
    elseif menu_active == 3 then
        draw_filename_input(menu_active)
        love.graphics.print(simple_message, 50, 300)
        if show_confirmation then
            draw_confirmation()
        end
    else
        draw_editor()
    end
end

function draw_menu(optionsToShow)
    love.graphics.setColor(color_text)
    for i, option in ipairs(optionsToShow) do
        if i == menu_index then
            love.graphics.setColor(color_text)
        else
            love.graphics.setColor(color_grey)
        end
        if #optionsToShow > screen_height-3 then 
            love.graphics.print(option, 50, (screen_height * cell_height/2) + (i - 1) * font_size - menu_index*cell_height)
        else 
            love.graphics.print(option, 50, 50 + (i - 1) * font_size)
        end
    end
end

function draw_filename_input(activeMenu)
    love.graphics.setColor(color_text)
    love.graphics.print("Input a filename: " .. new_filename .. ".screenplay", 50, 50)
end

function draw_confirmation()
    love.graphics.setColor(color_text)
    love.graphics.rectangle("fill", 100, 100, 600, 200)
    love.graphics.setColor(color_background)
    love.graphics.printf("Are you sure? (y/n)", 120, 140, 560, "center")
end


function draw_editor()
    for i = scroll_offset + 1, math.min(scroll_offset + screen_height, #doc) do
        local line = doc[i]
        
        if not line then
            goto continue
        end
        
        local text_width_reference_source = get_max_length_of_linetype(line.type)
        
        if line.type == "CHARACTER" or line.type == "PARENTHESIS" then 
            text_width_reference_source = #line.content
        end
        
        local text_xdraw_position = (screen_width * 0.5 - ((text_width_reference_source * 0.5))) * cell_width

        local within_block = i >= block_line_start and i <= block_line_end 

        if within_block then
            love.graphics.setColor(color_blockmarking)
        else
            if i == cursor_y then
                love.graphics.setColor(color_text)
            else
                love.graphics.setColor(color_grey)
            end
        end
        
        local line_draw_height = (line.visual_position - scroll_offset) * cell_height
        
        if show_linenumbers then
            local width = 5
            local formatted_number = string.format("%" .. width .. "d ", i)
            
            if i == jump_marker then
                formatted_number = "MARK"
            end

            love.graphics.print(formatted_number, 0, line_draw_height)
        end
        
        if not within_block then
            love.graphics.setColor(color_text)
        end
        
        local formatted_scene_number = ""
        
        if line.type == "SCENE" and not is_empty_or_whitespace(line.content) then
            local line_string = getSceneIndexBySceneLine(i) 
                        
            if not within_block then 
                love.graphics.setColor(color_scene)
            end
            
            formatted_scene_number = string.format("%3d ", line_string) 
        end
        
        local indent = 0
        if line.type == "ACTION" then
            indent = 1*indent_width
        elseif line.type == "CHARACTER" then
            indent = 3*indent_width
        elseif line.type == "DIALOGUE" then
            indent = 2*indent_width
        elseif line.type == "PARENTHESIS" then
            indent = 2*indent_width
        end
        
        local display_content = formatted_scene_number .. line.content
        if line.type == "SCENE" or line.type == "CHARACTER" then
            display_content = display_content:upper() 
        elseif line.type == "PARENTHESIS" then
            display_content = "(" .. display_content .. ")"
        end
        
        local linenumber_offset = 6
        
        if not show_linenumbers then 
            linenumber_offset = 1
        end

        text_xdraw_position = text_xdraw_position + (linenumber_offset * cell_width) 

        if function_active == "SEARCH" then 
            local search_lower = searchword:lower()
            local content_lower = display_content:lower()
            local search_position = content_lower:find(search_lower)
        
            if search_position then
                local match_start_index = search_position
                local match_end_index = match_start_index + #searchword - 1
        
                local full_line_length_before_match = display_content:sub(1, match_start_index - 1):len()
                
                local searchmark_start = (linenumber_offset + screen_width * 0.5 - ((text_width_reference_source * 0.5)))
                local start_x = (searchmark_start + full_line_length_before_match) * cell_width
                local end_x = (searchmark_start + full_line_length_before_match + #searchword) * cell_width
        
                local y_position = (line.visual_position - scroll_offset) * cell_height
        
                love.graphics.setColor(color_search) 
                love.graphics.rectangle("fill", start_x, y_position, end_x - start_x, cell_height)
                love.graphics.setColor(color_text)
            end
        end

        love.graphics.print(display_content, text_xdraw_position, (line.visual_position - scroll_offset) * cell_height)
        
        if i == cursor_y then
            local cursor_x = text_xdraw_position + ((cursor_position - 1 + #formatted_scene_number) * cell_width)
            love.graphics.print("▒", cursor_x, (line.visual_position - scroll_offset) * cell_height)
        end
	
        if i % page_size == 0 and show_pages then
            love.graphics.setColor(color_text) -- light grey color for the line
            local page_nr = tostring(math.floor(i/page_size)) 
            love.graphics.print(page_nr, (screen_width - 1 - #page_nr) * cell_width, line_draw_height)
            love.graphics.line(0, line_draw_height+cell_height, screen_width * cell_width, line_draw_height+cell_height)
        end
		
        ::continue::
    end

    local window_width, window_height = love.graphics.getWidth(), love.graphics.getHeight()
    local cell_width = math.floor(math.floor(font_size/2))
    local cell_height = math.floor(window_height / screen_height) -- Dynamically calculate cell height

    -- Draw the background rectangle
    love.graphics.setColor(color_text)
    love.graphics.rectangle("fill", 0, (screen_height - 1) * cell_height, window_width, cell_height)

    -- Draw the mode text
    love.graphics.setColor(color_background)
    love.graphics.print("MODE: " .. active_type, 5, (screen_height - 1) * cell_height)

    -- Determine the scene indicator text
    local scene_indicator_text = simple_message
    if simple_message == "" then
        scene_indicator_text = currentSceneNumber .. ": " .. currentSceneName
    end

    if function_active == "SEARCH" then 
        if simple_message == "" then 
            scene_indicator_text = "WORD SEARCH: ".. searchword
        end
    elseif function_active == "JUMP" then
        scene_indicator_text = "JUMP TO: ".. jump_to_location
    end

    -- Calculate text width for proper positioning
    local text_width = #scene_indicator_text * cell_width -- Adjust if a specific font is used
    local x_position = window_width - text_width - 10 -- Add padding to the right

    -- Draw the scene indicator text
    love.graphics.print(scene_indicator_text, x_position, (screen_height - 1) * cell_height)
end

function getSceneIndexBySceneLine(sceneLine)
    local scenes = getSceneList()

    for _, scene in ipairs(scenes) do
        if scene.line_number == sceneLine then
            return scene.scene_index
        end
    end

    return ""
end

function save_to_app_dir(filename)
    local file = io.open(dirPath .. "/" .. filename, "w")
    if file then
        file:write("LASTPOSITION|" .. cursor_y .. "\n")
        file:write("MARKPOSITION|" .. jump_marker .. "\n")
        for _, line in ipairs(doc) do
            file:write(line.type .. "|" .. line.content .. "\n")
        end
        file:close() 
        simple_message = "File saved as " .. filename
    else
        simple_message = "Failed to save the file."
    end
end

function load_from_app_dir(filename)
    local _file = io.open(dirPath .. "/" .. filename, "r")
    local cursor_start = 1 

    if not _file then
        simple_message = "Error: Unable to load file."
        return
    end

    doc = {}
    cursor_y = 1

    for _line in _file:lines() do
        local type, content = _line:match("^(%w+)|(.*)$")
        if type then
            if type == "LASTPOSITION" then 
                cursor_start = tonumber(content) 
            elseif type == "MARKPOSITION" then 
                jump_marker = tonumber(content) 
            else
                table.insert(doc, { type = type, content = sanitizeUTF8(content) or "", cursor_position = 1, visual_position = 0 })
            end 
        else
            print("Warning: Malformed line ignored:", _line)
        end
    end

    _file:close()
    simple_message = "File loaded from application directory: " .. filename
    
    cursor_y = cursor_start 
    centerScroll() 
    update_display_text()
end

-- function sanitizeUTF8(str)
--     local clean = {}
--     local len = #str

--     for i = 1, len do
--         local byte = str:byte(i)
--         if byte == string.byte("|") then
--             table.insert(clean, "|")
--         elseif byte >= 0x20 and byte <= 0x7E then
--             table.insert(clean, string.char(byte))
--         else
--             table.insert(clean, "?")
--         end
--     end

--     return table.concat(clean)
-- end

function sanitizeUTF8(str)
    local clean = {}
    local len = #str
    local i = 1

    while i <= len do
        local byte = str:byte(i)

        if byte == string.byte("|") then
            -- Allow the pipe character ('|') to pass through
            table.insert(clean, "|")
            i = i + 1
        elseif byte >= 0x20 and byte <= 0x7E then
            -- Valid printable ASCII characters
            table.insert(clean, string.char(byte))
            i = i + 1
        elseif byte == 0xE2 and str:byte(i + 1) == 0x80 then
            -- Check for specific multi-byte characters like "—" (long dash)
            if str:byte(i + 2) == 0x94 then
                -- Long dash "—" (UTF-8: E2 80 94)
                table.insert(clean, "-")  -- Replace with a single-byte dash
                i = i + 3  -- Skip over the 3 bytes of the long dash
            -- Right single quotation mark (’)
            elseif str:byte(i + 2) == 0x99 then
                table.insert(clean, "'")  -- Replace with a single-byte apostrophe
                i = i + 3  -- Skip over the 3 bytes of the right single quote
            -- Left single quotation mark (‘)
            elseif str:byte(i + 2) == 0x98 then
                table.insert(clean, "'")  -- Replace with a single-byte apostrophe
                i = i + 3  -- Skip over the 3 bytes of the left single quote
            -- Handle double curly quotes (left: “, right: ”)
            elseif str:byte(i + 2) == 0x9C then
                table.insert(clean, '"')  -- Replace with a single-byte double quote
                i = i + 3  -- Skip over the 3 bytes
            elseif str:byte(i + 2) == 0x9D then
                table.insert(clean, '"')  -- Replace with a single-byte double quote
                i = i + 3  -- Skip over the 3 bytes
            else
                table.insert(clean, "?")
                i = i + 1
            end
        else
            -- Handle any other multi-byte or unknown characters
            table.insert(clean, "?")
            i = i + 1
        end
    end

    return table.concat(clean)
end


function is_empty_or_whitespace(str)
    return str == nil or str:match("^%s*$") ~= nil
end

function go_to_next_scene()
    local original_y = cursor_y
    repeat
        cursor_y = cursor_y + 1
        if cursor_y > #doc then
            cursor_y = 1
        end
        local line = doc[cursor_y]
        if line and line.type == "SCENE" and not is_empty_or_whitespace(line.content) then
            centerScroll()
            cursor_position = 1 
            return
        end
    until cursor_y == original_y 
end

function go_to_previous_scene()
    local original_y = cursor_y
    repeat
        cursor_y = cursor_y - 1
        if cursor_y < 1 then
            cursor_y = #doc 
        end
        local line = doc[cursor_y]
        if line and line.type == "SCENE" and not is_empty_or_whitespace(line.content) then
            centerScroll()
            cursor_position = 1 
            return
        end
    until cursor_y == original_y 
end

function getClosestScene(cursor_y)
    for line_number = cursor_y, 1, -1 do
        local line = doc[line_number]
        if line and line.type == "SCENE" and not is_empty_or_whitespace(line.content) then
            currentSceneNumber = getSceneIndexBySceneLine(line_number)
            return string.upper(line.content)
        end
    end
    return "" 
end

function loadSettings()
    local settings = {
        show_linenumbers = false,  -- Default value
        indent_width = 8,          -- Default value
        backup_timer = 300,          -- Default value
        backup_directory = "backups",
        max_backups = 10,
        export_directory = "exports",
        max_linewidth_action = 60, 
        max_linewidth_dialogue = 35,
        max_linewidth_scene = 80,
        max_linewidth_character = 35,
        max_linewidth_parenthesis = 35,
        fontSize = 32,
        fontPath = "assets/ModernDOS8x16.ttf",
        pageSize = 52,
        fullscreen = true, 
        resizable = false, 
        show_pages = true,
        color_text = "1, 1, 1",
        color_background = "0, 0, 0",
        color_scene = "1, 1, 0",
        color_blockmarking = "1, 0, 0",
        color_search = "0.5, 0.5, 0",
        color_grey = "0.5, 0.5, 0.5",
    }

    local file = io.open(dirPath.."/".."settings.ini", "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("([^=]+)%s*=%s*(.+)")
            if key and value then
                key = key:trim()
                value = value:trim()

                -- Convert boolean strings to actual booleans
                if value == "true" then
                    settings[key] = true
                elseif value == "false" then
                    settings[key] = false
                else
                    -- Convert number values
                    local num = tonumber(value)
                    settings[key] = num or value  -- If it's not a number, store the string value
                end
            end
        end
        file:close()
    end

    return settings
end

function string:trim()
    return self:match("^%s*(.-)%s*$")
end

function saveSettings(settings)
    local file = io.open(dirPath.."/".."settings.ini", "w")
    if file then
        for key, value in pairs(settings) do
            -- Convert booleans to "true" or "false"
            if type(value) == "boolean" then
                value = value and "true" or "false"
            end
            file:write(key .. " = " .. tostring(value) .. "\n")
        end
        file:close()
    end
end

function exportToTXT(file_open)
    os.execute("mkdir -p " .. dirPath .. "/" .. export_directory)

    local file_name = file_open:gsub("%.screenplay$", "")
    local file_to_export = string.format("%s/%s.txt", dirPath .. "/" .. export_directory, file_name)
    local file = io.open(file_to_export, "w")
    print(file_to_export)

    if not file then
        simple_message = "Error opening file for writing."
        return
    end

    for _, line in ipairs(doc) do
        local content = line.content or ""  

        if line.type == "SCENE" then
            content = string.upper(content)
        elseif line.type == "ACTION" then
            content = string.rep(" ", indent_width) .. content
        elseif line.type == "DIALOGUE" or line.type == "PARENTHESIS" then
            content = string.rep(" ", indent_width * 2) .. content
        elseif line.type == "CHARACTER" then
            content = string.rep(" ", indent_width * 3) .. content
        end

        file:write(content .. "\n")
    end

    file:close()
end

function getCurrentTime()
    local date = os.date("*t")
    return string.format("%04d-%02d-%02d_%02d-%02d-%02d", 
                         date.year, date.month, date.day, 
                         date.hour, date.min, date.sec)
end

function createBackup(open_file)
    os.execute("mkdir -p " .. dirPath .. "/" ..  backup_directory)

    local timestamp = getCurrentTime()
    local filename = string.format("%s/backup_%s_%s", dirPath .. "/" .. backup_directory, timestamp, open_file)
    
    local file = io.open(filename, "w")
    if file then
        
        for _, line in ipairs(doc) do
            file:write(line.type .. "|" .. line.content .. "\n")
        end
        file:close() 
        simple_message = "Backup saved. " 
    else
        simple_message = "Failed to save backup."
    end

    manageBackups()
end

function manageBackups()
    local files = {}
    for file in io.popen('ls -t ' .. dirPath .. "/" .. backup_directory):lines() do
        table.insert(files, file)
    end

    while #files > max_backups do
        os.remove(dirPath .. "/" .. backup_directory .. "/" .. files[#files])
        table.remove(files, #files)
    end
end

function centerScroll() 
    scroll_offset = math.max(0, math.min(#doc - screen_height + bottom_margin, cursor_y - scroll_margin))
end

function go_to_previous_line_of_different_type()
    if #doc == 0 then return end -- Ensure the document has content
    local original_type = doc[cursor_y].type
    local index = cursor_y

    repeat
        index = index - 1
        if index < 1 then
            index = #doc -- Wrap to the last line
        end
        if doc[index].content ~= "" and doc[index].content ~= nil and (doc[index].type ~= original_type or doc[index].type == "SCENE") then
            cursor_y = index
            cursor_position = 1
            centerScroll()
            return
        end
    until index == cursor_y -- Stop if we wrap around completely
end

function go_to_next_line_of_different_type()
    if #doc == 0 then return end -- Ensure the document has content
    local original_type = doc[cursor_y].type
    local index = cursor_y

    repeat
        index = index + 1
        if index > #doc then
            index = 1 -- Wrap to the first line
        end
        if doc[index].content ~= "" and doc[index].content ~= nil and (doc[index].type ~= original_type or doc[index].type == "SCENE") then
            cursor_y = index
            cursor_position = 1
            centerScroll() -- Adjust the scroll position if necessary
            return
        end
    until index == cursor_y -- Stop if we wrap around completely
end
