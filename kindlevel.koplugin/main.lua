-- Keep this entry point small: recovery must not depend on the reading app.
local root=assert(debug.getinfo(1,"S").source:match("^@(.+)/main%.lua$"))
return dofile(root .. "/kindlevel_bootstrap.lua").load(root)
