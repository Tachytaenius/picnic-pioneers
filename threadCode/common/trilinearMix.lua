local function mix(a, b, t)
	return a + t * (b - a)
end

return function(
	-- Negative/positive
	nnn, nnp, npn, npp,
	pnn, pnp, ppn, ppp,
	mixX, mixY, mixZ
)
	return mix( -- z mix
		mix( -- y mix for -z
			mix( -- x mix for -y -z
				nnn,
				pnn,
				mixX
			),
			mix( -- x mix for +y -z
				npn,
				ppn,
				mixX
			),
			mixY
		),
		mix( -- y mix for +z
			mix( -- x mix for -y +z
				nnp,
				pnp,
				mixX
			),
			mix( -- x mix for +y +z
				npp,
				ppp,
				mixX
			),
			mixY
		),
		mixZ
	)
end
