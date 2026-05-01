uniform float shape_densityExponent;
uniform float shape_armCount;
uniform float shape_armEndRotation;

const float shape_coreProportion = 0.175;
const float shape_coreFullProportion = 0.25;

vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, s, -s, c);
	return m * v;
}

float sampleShapeDensity(vec3 samplePosition) {
	float samplePositionElevation = samplePosition.z;
	vec2 samplePosition2D = samplePosition.xy;
	float swirlAngle = shape_armEndRotation * length(samplePosition2D);
	vec2 samplePosition2DSwirled = rotate(samplePosition2D, swirlAngle);
	vec3 samplePositionSwirled = vec3(
		samplePosition2DSwirled,
		samplePositionElevation
	);

	float galaxyCoreFactor = clamp(
		(length(samplePosition2D) - shape_coreFullProportion) / (shape_coreProportion - shape_coreFullProportion),
		0.0, 1.0
	);

	float armVerticalTaperEnd = 1.0 - 0.9 * min(1.0, length(samplePosition2D));
	float armVerticalTaperStart = armVerticalTaperEnd * 0.8;
	float armVerticalTaper = clamp(
		(abs(samplePositionElevation) - armVerticalTaperEnd) / (armVerticalTaperStart - armVerticalTaperEnd),
		0.0, 1.0
	);

	float armFactor = armVerticalTaper * pow(
		sin(atan(samplePosition2DSwirled.y, samplePosition2DSwirled.x) * shape_armCount) * 0.5 + 0.5,
		3.3 * length(samplePosition2D)
	);
	float baseDensity = mix( // Mix between spiral arms and core with no arms
		armFactor,
		1.0,
		galaxyCoreFactor
	);

	return pow(
		max(0.0, baseDensity * (1.0 - length(samplePosition))),
		shape_densityExponent
	);
}
