-- Compatibility entry point for the native species update journal.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
return dofile(dir..'/notice_journal_ui.lua')
