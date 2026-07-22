struct Point {
#ifdef FEATURE_POSITION
	vec3 position;
#endif
#ifdef FEATURE_LUMINOUS_FLUX
	vec3 luminousFlux;
#endif
#ifdef FEATURE_SHAPE_TYPE_SUBTYPE
	uvec2 shapeTypeSubtypeIds;
#endif
#ifdef FEATURE_ATTENUATION_SHAPE_TYPE_SUBTYPE
	uvec2 attenuationShapeTypeSubtypeIds;
#endif
#ifdef FEATURE_ATTENUATION_MULTIPLIER
	float attenuationMultiplier;
#endif
#ifdef FEATURE_RADII
	vec3 radii;
#endif
#ifdef FEATURE_MASS
	float mass;
#endif
};

readonly buffer Points {
	Point points[];
};
