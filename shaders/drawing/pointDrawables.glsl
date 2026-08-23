#pragma language glsl4

const float tau = 6.28318530717958647692528676655900576839433879875021164194988918461563281257241799725606965068423413; // Thanks OEIS (silly)

// Assumes additive mode on a canvas with float colours

varying float fade;
varying vec3 colour;

uniform float fadeExponent;

uniform float angularRadius;
// These depend on angular radius
uniform float diskDistanceToSphere;
uniform float scale;

#ifdef VERTEX

#ifdef INSTANCED
struct PointDrawable {
	vec3 direction;
	vec3 radiance;
};
readonly buffer PointDrawables {
	PointDrawable pointDrawables[];
};
#else
uniform vec3 direction;
uniform vec3 radiance;
uniform sampler3D pointAttenuationTexture;
uniform sampler2D totalTransmittanceCanvas;
uniform vec3 attenuationTextureCoords;
#endif

uniform vec3 cameraUp;
uniform vec3 cameraRight;
uniform mat4 skyToClip;

layout (location = 0) in vec2 VertexPosition;
layout (location = 1) in float VertexFade;

void vertexmain() {
	fade = VertexFade;

#ifdef INSTANCED
	uint i = gl_InstanceID;
	PointDrawable pointDrawable = pointDrawables[i];
	colour = pointDrawable.radiance;
	vec3 direction = pointDrawable.direction;
#else
	vec2 totalTransmittanceCoord = vec2(attenuationTextureCoords.x, 1.0 - attenuationTextureCoords.y);
	float transmittance =
		texture(pointAttenuationTexture, attenuationTextureCoords).r *
		texture(totalTransmittanceCanvas, totalTransmittanceCoord).r;
	colour = radiance * transmittance;
#endif

	vec3 billboardRight = cross(cameraUp, direction);
	if (length(billboardRight) == 0.0) {
		// Singularity
		billboardRight = cameraRight;
	}
	vec3 billboardUp = cross(direction, billboardRight);
	vec3 centre = direction * (1.0 - diskDistanceToSphere);
	float effectiveScale = colour == vec3(0.0) ? 0.0 : scale; // Draw no fragments if no brightness
	vec3 celestialSpherePos = centre + effectiveScale * (billboardRight * VertexPosition.x + billboardUp * VertexPosition.y);
	gl_Position = skyToClip * vec4(celestialSpherePos, 1.0);
}

#endif

#ifdef PIXEL

out vec4 outColour;

void pixelmain() {
	// float shape = 1.0;
	float shape = pow(1.0 - fade, fadeExponent); // Must match graphics.lua's version of this line
	// Compensating for the shape not being constantly 1 is done with the pointOutputMultiplier variable CPU-side

	outColour = shape * vec4(colour, 1.0);
}

#endif 
