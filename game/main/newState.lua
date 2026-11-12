local consts = require("consts")
local util = require("util")

local game = {}

function game:newState()
	local state = {}

	setmetatable(state, {
		__index = self -- self is the full game table (rather than the file-local one here) if this is called as game:newState(), which it should be
	})

	return state
end

function game:loadXYZFromWavelengthData()
	local xyzFromWavelength = {}
	for line in love.filesystem.lines("data/CIE_xyz_1931_2deg.csv") do
		local wavelength, x, y, z = line:match("([^,]*),([^,]*),([^,]*),([^,]*)")
		xyzFromWavelength[tonumber(wavelength)] = {
			x = tonumber(x),
			y = tonumber(y),
			z = tonumber(z)
		}
	end
	return xyzFromWavelength
end

function game:initSpectralInfo()
	-- 3 bins of equal size over the visible wavelength range ("RGB") are used in the physical rendering
	-- and then converted to CIE XYZ, and then to sRGB. Which is not what the renderer was using.

	-- Wavelengths are in nm here

	local xyzFromWavelength = self:loadXYZFromWavelengthData()

	-- 400 nm to 700 nm
	local step = 100

	self.rSpectrumStart = 600
	self.rSpectrumEnd = 700
	self.rSpectrumMiddle = (self.rSpectrumStart + self.rSpectrumEnd) / 2

	self.gSpectrumStart = 500
	self.gSpectrumEnd = 600
	self.gSpectrumMiddle = (self.gSpectrumStart + self.gSpectrumEnd) / 2

	self.bSpectrumStart = 400
	self.bSpectrumEnd = 500
	self.bSpectrumMiddle = (self.bSpectrumStart + self.bSpectrumEnd) / 2

	local function bin(start, stop)
		local sumX, sumY, sumZ = 0, 0, 0
		for wavelength = start, stop - 1 do
			local xyz = xyzFromWavelength[wavelength]
			sumX = sumX + xyz.x
			sumY = sumY + xyz.y
			sumZ = sumZ + xyz.z
		end
		return sumX / step, sumY / step, sumZ / step
	end

	local rX, rY, rZ = bin(self.rSpectrumStart, self.rSpectrumEnd)
	local gX, gY, gZ = bin(self.gSpectrumStart, self.gSpectrumEnd)
	local bX, bY, bZ = bin(self.bSpectrumStart, self.bSpectrumEnd)

	local k = 1e-9 -- Conversion factor from W/sr/m^2/nm to W/sr/m^2/m
	self.spectralToXYZMatrix = { -- Row-major
		k*rX, k*gX, k*bX,
		k*rY, k*gY, k*bY,
		k*rZ, k*gZ, k*bZ
	}
end

function game:initState(initParams)
	-- Common graphics init
	self.screenCanvasses = {} -- Canvasses for which the size is supposed to match the game output size. There are also scaled canvasses like those in point layers for their volumetrics or the point attenuation texture
	self.screenWidth, self.screenHeight = love.graphics.getDimensions()
	self.dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))

	self:initSpectralInfo()

	self:initShip(initParams)
	self:initCelestial(initParams)
	self:resizeGameScreen(self.screenWidth, self.screenHeight, true)

	self.spectralToRGBShader = love.graphics.newShader("shaders/drawing/spectralToRGB.glsl")
end

---@param width number
---@param height number
---@param forceRecreate boolean
--- resizeGameScreen sets game.screenWidth and game.screenHeight.
--- It also recreates each canvas in screenCanvasses and the canvasses for each PointLayer with the updated dimensions, if necessary.
function game:resizeGameScreen(width, height, forceRecreate)
	local changed = width ~= self.screenWidth or height ~= self.screenHeight
	if not changed and not forceRecreate then
		return
	end

	for _, canvas in ipairs(self.screenCanvasses) do
		canvas:release()
	end

	self.screenWidth = width
	self.screenHeight = height
	self.volumetricCanvasWidth = math.ceil(consts.volumetricCanvasScale * self.screenWidth)
	self.volumetricCanvasHeight = math.ceil(consts.volumetricCanvasScale * self.screenHeight)

	self.screenCanvasses.pointTotalTransmittanceCanvas = love.graphics.newCanvas(width, height, { -- Gets multiplied down as the camera progresses out from the smallest layer to the largest. Distinct from the point attenuation texture because that is recalculated per-layer
		format = "rgba16f",
		debugname = "Point Total Transmittance Canvas",
		computewrite = true
	})
	self.screenCanvasses.outputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f",
		debugname = "Output Canvas",
		computewrite = true
	})
	self.screenCanvasses.shipCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba8",
		debugname = "Ship Canvas"
	})

	self.pointAttenuationTexture = love.graphics.newCanvas(
		math.ceil(width * consts.pointAttenuationTextureScale),
		math.ceil(height * consts.pointAttenuationTextureScale),
		consts.pointAttenuationTextureSteps,
		{
			type = "volume",
			format = "rgba16f",
			computewrite = true,
			debugname = "Point Attenuation Texture"
		}
	)
	self.pointAttenuationTexture:setFilter("linear")
	self.pointAttenuationTexture:setWrap("clamp", "clamp", "clamp")

	for _, pointLayer in ipairs(self.pointLayers) do
		if pointLayer.volumetricCanvas then
			pointLayer.volumetricCanvas:release()
		end
		if pointLayer.volumetricAddCountCanvas then
			pointLayer.volumetricAddCountCanvas:release()
		end

		-- pointLayer.volumetricCanvasCameraInfo = nil -- Not needed since the new canvas is ready for new rays to add in
		pointLayer.volumetricCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Canvas",
			format = "rgba32f", -- 32 bits to maintain precision when adding up. When drawing the value of the point total transmittance canvas, it was shown to become imprecise (banding and other artifacts) after a while with 16 bits.
			computewrite = true
		})
		pointLayer.volumetricOpacityCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Opacity Canvas",
			format = "rgba16f",
			computewrite = true
		})
		pointLayer.volumetricAddCountCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Addition Count Canvas",
			format = "r8ui",
			computewrite = true
		})
	end
end

return game
