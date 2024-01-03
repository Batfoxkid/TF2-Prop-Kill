/*
	SpawnTemplate will randomly set the template to the name with a random number,
	so the results will be "prop3", random number starts from 1 and ends with choosen number.
	Have props named this way such as a template named "prop6" will randomly be choosen to spawn.

	Including the script "randommarker.nut" will also shuffle the spawning angles for the maker.
*/

IncludeScript("randommaker.nut");
SpawnTemplate("prop", 6);