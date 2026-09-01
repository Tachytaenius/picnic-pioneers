float SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	return
		max(0.0, 1.0 - length(samplePosition)) * (
			2.0 * VALUE_NOISE(1, samplePositionTrueRatio) +
			PARAM(nebulaMultiplier) * pow(
				(
					VALUE_NOISE(2, samplePositionTrueRatio) +
					VALUE_NOISE(3, samplePositionTrueRatio) +
					VALUE_NOISE(4, samplePositionTrueRatio)
				) / 3.0,
				PARAM(nebulaExponent)
			)
		);
}
