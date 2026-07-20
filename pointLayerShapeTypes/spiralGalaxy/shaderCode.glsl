vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, s, -s, c);
	return m * v;
}

float SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	float originalLength3D = length(samplePosition);
	if (originalLength3D > 1.0) {
		return 0.0;
	}
	vec3 offset = PARAM(noiseOffsetSize) * (vec3(
		VALUE_NOISE(1, samplePosition),
		VALUE_NOISE(2, samplePosition),
		VALUE_NOISE(3, samplePosition)
	) * 2.0 - 1.0) / vec3(1.0, 1.0, PARAM(averageZRatio));
	samplePosition = samplePosition + offset;

	float samplePositionElevation = samplePosition.z;
	vec2 samplePosition2D = samplePosition.xy;
	float swirlAngle = PARAM(armEndRotation) * length(samplePosition2D);
	vec2 samplePosition2DSwirled = rotate(samplePosition2D, swirlAngle);
	vec3 samplePositionSwirled = vec3(
		samplePosition2DSwirled,
		samplePositionElevation
	);

	float galaxyCoreFactor = clamp(
		(length(vec3(samplePosition.xy, samplePosition.z / 3.0)) - PARAM(coreFullProportion)) / (PARAM(coreProportion) - PARAM(coreFullProportion)),
		0.0, 1.0
	);

	float armVerticalTaperEnd = 1.0 - 0.9 * min(1.0, length(samplePosition2D));
	float armVerticalTaperStart = armVerticalTaperEnd * 0.05;
	float armVerticalTaper = pow(clamp(
		(abs(samplePositionElevation) - armVerticalTaperEnd) / (armVerticalTaperStart - armVerticalTaperEnd),
		0.0, 1.0
	), PARAM(armVerticalTaperPower));

	float armFactor = armVerticalTaper * pow(
		sin(atan(samplePosition2DSwirled.y, samplePosition2DSwirled.x) * PARAM(armCount)) * 0.5 + 0.5,
		3.3 * length(samplePosition2D)
	);
	float baseDensity = mix( // Mix between spiral arms and core with no arms
		armFactor,
		1.0,
		galaxyCoreFactor
	);

	return pow(
		max(0.0, baseDensity * (1.0 - originalLength3D)),
		PARAM(densityExponent)
	);
}
