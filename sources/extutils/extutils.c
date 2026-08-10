#include <fenv.h>

extern int ensureRoundingMode(void) {
	int wasOK = fegetround() == FE_TONEAREST;
	fesetround(FE_TONEAREST);
	return wasOK;
}
