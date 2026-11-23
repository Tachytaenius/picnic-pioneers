struct PointDrawable {
	vec3 direction;
	vec3 radiance;
};
writeonly buffer PointDrawables {
	PointDrawable pointDrawables[];
};

struct IndirectDrawArgs {
	uint vertexCount;
	uint instanceCount;
	uint baseVertex;
	uint baseInstance;
};
buffer IndirectDrawBuffer {
	IndirectDrawArgs indirectDrawBuffer[];
};

uniform vec3 direction;
uniform vec3 unattenuatedRadiance;
uniform sampler3D pointAttenuationTexture;
uniform vec3 attenuationTextureCoords;
uniform sampler2D totalTransmittanceCanvas;
uniform bool useDepthCanvas;
uniform sampler2D shipDepthCanvas;
uniform float far;
uniform float near;
uniform float pointZ;

float depthToLinear(float depth) {
	return (2.0 * near * far) / (far + near - (depth * 2.0 - 1.0) * (far - near));
}

layout (local_size_x = 1) in;
void computemain() {
	uint insertIndex = atomicAdd(indirectDrawBuffer[0].instanceCount, 1);
	vec3 radiance = unattenuatedRadiance;
	vec2 totalTransmittanceCoord = vec2(attenuationTextureCoords.x, 1.0 - attenuationTextureCoords.y);
	vec3 transmittance =
		texture(pointAttenuationTexture, attenuationTextureCoords).rgb *
		texture(totalTransmittanceCanvas, totalTransmittanceCoord).rgb;
	if (useDepthCanvas) {
		float depthSample = texture(shipDepthCanvas, totalTransmittanceCoord).r;
		if (depthSample < 1.0) {
			float opaqueZ = depthToLinear(depthSample);
			if (opaqueZ < pointZ) {
				transmittance = vec3(0.0);
			}
		}
	}
	radiance *= transmittance;
	pointDrawables[insertIndex] = PointDrawable (direction, radiance);
}
