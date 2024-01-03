function RollAngle()
{
	return (rand() % 360) - 180.0;
}

function SpawnTemplate(name, count)
{
	NetProps.SetPropString(self, "m_iszTemplate", name + ((rand() % count) + 1));
	EntFireByHandle(self, "ForceSpawn", "", -1.0, self, self);
}

local angles = QAngle(0.0, RollAngle(), 0.0);
self.Teleport(false, self.GetOrigin(), true, angles, false, self.GetVelocity());