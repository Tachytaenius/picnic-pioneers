struct Point {
#ifdef FEATURE_POSITION
	vec3 position;
#endif
#ifdef FEATURE_LUMINOUS_INTENSITY
	vec3 luminousIntensity;
#endif
#ifdef FEATURE_ORIENTATION
	vec4 orientation; // Quaternion
#endif
};

readonly buffer Points {
	Point points[];
};
