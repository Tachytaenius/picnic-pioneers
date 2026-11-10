vec3 SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	return vec3(
		max(0.0, 1.0 - length(samplePosition)) * (
			2.0 * VALUE_NOISE(1, samplePositionTrueRatio) + // Multiply the noise by 2 to give an average of 1 so that the object's attenuation multiplier is more or less the average
			PARAM(nebulaMultiplier) * pow(
				(
					2.0 * VALUE_NOISE(2, samplePositionTrueRatio) +
					2.0 * VALUE_NOISE(3, samplePositionTrueRatio) +
					VALUE_NOISE(4, samplePositionTrueRatio)
				) / 5.0,
				PARAM(nebulaExponent)
			)
		)
	) * vec3(
		VALUE_NOISE(5, samplePositionTrueRatio),
		VALUE_NOISE(6, samplePositionTrueRatio),
		VALUE_NOISE(7, samplePositionTrueRatio)
	);
}
