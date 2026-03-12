local consts = require("consts")

return function(segments)
	local centreVertex = {
		-- No z
		0, 0, -- 0,
		0 -- This is VertexFade
	}
	local edgeVertices = {} -- Starts at 0
	for i = 0, segments - 1 do
		local angle = consts.tau * i / segments
		edgeVertices[i] = {
			math.cos(angle), math.sin(angle), -- 0,
			1
		}
	end
	local vertices = {}
	for i = 0, segments - 1 do
		vertices[#vertices+1] = edgeVertices[i]
		vertices[#vertices+1] = edgeVertices[(i + 1) % segments]
		vertices[#vertices+1] = centreVertex
	end
	return love.graphics.newMesh(consts.pointDiskVertexFormat, vertices, "triangles"), #vertices
end
