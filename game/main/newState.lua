local consts = require("consts")
local mathsies = require("lib.mathsies")

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

	-- Wavelengths are in nm here for interpreting the data
	-- They are then converted to m

	local xyzFromWavelength = self:loadXYZFromWavelengthData()

	local rSpectrumStart = 626
	local rSpectrumEnd = 750
	local rSpectrumMiddle = (rSpectrumStart + rSpectrumEnd) / 2

	local gSpectrumStart = 503
	local gSpectrumEnd = 626
	local gSpectrumMiddle = (gSpectrumStart + gSpectrumEnd) / 2

	local bSpectrumStart = 380
	local bSpectrumEnd = 503
	local bSpectrumMiddle = (bSpectrumStart + bSpectrumEnd) / 2

	-- 400 nm to 700 nm in 3 bins
	local range = (rSpectrumEnd - bSpectrumStart) / 3

	local function bin(start, stop)
		local sumX, sumY, sumZ = 0, 0, 0
		local count = 0
		for wavelength = start, stop - 1 do
			local xyz = xyzFromWavelength[wavelength]
			sumX = sumX + xyz.x
			sumY = sumY + xyz.y
			sumZ = sumZ + xyz.z
			count = count + 1
		end
		return sumX / count, sumY / count, sumZ / count -- Average values of X, Y, and Z across the bin
	end

	local rX, rY, rZ = bin(rSpectrumStart, rSpectrumEnd)
	local gX, gY, gZ = bin(gSpectrumStart, gSpectrumEnd)
	local bX, bY, bZ = bin(bSpectrumStart, bSpectrumEnd)

	local f = 1e-9 -- Conversion factor from nm^-1 to m^-1

	local b = f * range -- Width of a bin in m

	self.spectralToXYZMatrix = mathsies.mat4( -- Row-major
		b*rX, b*gX, b*bX, 0,
		b*rY, b*gY, b*bY, 0,
		b*rZ, b*gZ, b*bZ, 0,
		0, 0, 0, 1
	)
	self.xyzToRGBMatrix = mathsies.mat4(
		3.2406255, -1.5372080, -0.4986286, 0,
		-0.9689307, 1.8757561, 0.0415175, 0,
		0.0557101, -0.2040211, 1.0569959, 0,
		0, 0, 0, 1
	)
	self.spectralToRGBMatrix = self.xyzToRGBMatrix * self.spectralToXYZMatrix
	local m = self.spectralToRGBMatrix
	self.spectralToRGBMatrix3x3 = {
		m._00, m._01, m._02,
		m._10, m._11, m._12,
		m._20, m._21, m._22
	}

	self.xyzToSpectralMatrix = mathsies.mat4.inverse(self.spectralToXYZMatrix)
	self.rgbToXYZMatrix = mathsies.mat4(
		0.4124, 0.3576, 0.1805, 0,
		0.2126, 0.7152, 0.0722, 0,
		0.0193, 0.1192, 0.9505, 0,
		0, 0, 0, 1
	)
	self.rgbToSpectralMatrix = self.xyzToSpectralMatrix * self.rgbToXYZMatrix -- Not to be used directly as it can cause negative spectral radiances. See the function rgbToSpectralRadiance

	self.spectralBinRange = b

	self.rSpectrumStart = rSpectrumStart * f
	self.rSpectrumEnd = rSpectrumEnd * f
	self.rSpectrumMiddle = rSpectrumMiddle * f

	self.gSpectrumStart = gSpectrumStart * f
	self.gSpectrumEnd = gSpectrumEnd * f
	self.gSpectrumMiddle = gSpectrumMiddle * f

	self.bSpectrumStart = bSpectrumStart * f
	self.bSpectrumEnd = bSpectrumEnd * f
	self.bSpectrumMiddle = bSpectrumMiddle * f
end

function game:initState(initParams)
	-- Common graphics init
	self.screenCanvasses = {} -- Canvasses for which the size is supposed to match the game output size. There are also scaled canvasses like those in point layers for their volumetrics or the point attenuation texture
	self.screenWidth, self.screenHeight = love.graphics.getDimensions()
	local vertices = {
		{-1, -1}, {-1, 1}, {1, -1},
		{-1, 1}, {1, 1}, {1, -1}
	}
	local format = {
		{name = "VertexPosition", location = 0, format = "floatvec2"}
	}
	self.dummyMesh = love.graphics.newMesh(format, vertices, "triangles")

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

	self.screenCanvasses.transmittanceCanvas = love.graphics.newCanvas(width, height, { -- Gets multiplied down as the camera progresses out from the smallest/"closest" layer to the largest. Distinct from the point attenuation texture because that is recalculated per-layer
		format = "rgba16f",
		debugname = "Transmittance Canvas",
		computewrite = true
	})
	self.screenCanvasses.tempOpacityCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba16f",
		debugname = "Temporary Opacity Canvas",
		computewrite = true
	})
	self.screenCanvasses.lightCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f",
		debugname = "Light Canvas",
		computewrite = true
	})
	self.screenCanvasses.opaqueObjectLightCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f",
		debugname = "Opaque Object Light Canvas"
	})
	self.screenCanvasses.shipDepthCanvas = love.graphics.newCanvas(width, height, {
		format = "depth24",
		readable = true,
		debugname = "Ship Depth Canvas"
	})

	self.screenCanvasses.shipCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f",
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
			debugname = pointLayer.debugName .. " Volumetric Radiance Canvas",
			format = "rgba32f", -- 32 bits to maintain precision when adding up. When drawing the value of the point total transmittance canvas, it was shown to become imprecise (banding and other artifacts) after a while with 16 bits.
			computewrite = true
		})
		pointLayer.volumetricTransmittanceCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Transmittance Canvas",
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
