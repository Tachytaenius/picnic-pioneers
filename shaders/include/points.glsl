struct Point {
#ifdef FEATURE_POSITION
	vec3 position;
#endif
#ifdef FEATURE_RADIANT_INTENSITY
	float radiantIntensity;
#endif
#ifdef FEATURE_ORIENTATION
	vec4 orientation; // Quaternion
#endif
};

readonly buffer Points {
	Point points[];
};
