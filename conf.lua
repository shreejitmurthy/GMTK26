_G.config = {
    title = "GMTK26",
    width = 1280,
    height = 720,
}

function love.conf(t) 
    t.window = config
    t.window.resizable = config.resizable
end