singularity = class({})

-- Add the charging modifier.
function singularity:OnSpellStart()
	local particle = ParticleManager:CreateParticleForTeam("particles/heroes/enigma/singularity_tracer.vpcf", PATTACH_WORLDORIGIN, self:GetCaster(), self:GetCaster():GetTeam())
	ParticleManager:SetParticleControl(particle, 0, self:GetCursorPosition())
	self:GetCaster():AddNewModifier(self:GetCaster(), self, "modifier_singularity_charging", {duration = self:GetSpecialValueFor("charge_time"), target = self:GetCursorPosition(), particle = particle})
end

function singularity:GetCastAnimation()
	return ACT_DOTA_CAST_ABILITY_1
end

---

LinkLuaModifier("modifier_singularity_charging", "heroes/enigma/singularity", LUA_MODIFIER_MOTION_NONE)
modifier_singularity_charging = class({})

function modifier_singularity_charging:OnCreated(info)
	if not IsServer() then return end
	-- Add the cancel ability
	self:GetCaster():SwapAbilities("singularity", "collapse_singularity", false, true)

	-- Just save this for later
	self.particle = info.particle
	self.start_time = GameRules:GetGameTime()

	-- For some reason vectors get passed as space-delimited strings, so we need to re-parse it into a vector
	local values = split(info.target, " ")
	self.target = Vector(values[1], values[2], values[3])

	-- This thinker doesn't actually do anything on its own -- BUT, if it gets destroyed, then it was destroyed during round cleanup and we should not create the singularity
	self.chargethinker = CreateModifierThinker(self:GetAbility():GetCaster(), self:GetAbility(), "modifier_singularity_charging_thinker", {duration = self:GetAbility():GetSpecialValueFor("charge_time") + 1}, self.target, self:GetAbility():GetCaster():GetTeam(), false)
end

-- Using the sub-ability removes the modifier, so this function gets called at the right time either way
function modifier_singularity_charging:OnDestroy()
	if not IsServer() then return end
	-- Delete particles
	ParticleManager:DestroyParticle(self.particle, false)

	-- Remove the cancel ability
	self:GetCaster():SwapAbilities("singularity", "collapse_singularity", true, false)

	-- Set a strength multiplier based on how long we charged for (as a % of the max)
	local strength = (GameRules:GetGameTime() - self.start_time) / self:GetAbility():GetSpecialValueFor("charge_time")

	-- see above
	if not self.chargethinker:IsNull() then
		-- Create the singularity
		CreateModifierThinker(self:GetAbility():GetCaster(), self:GetAbility(), "modifier_singularity_thinker", {duration = self:GetAbility():GetSpecialValueFor("singularity_duration"), strength = strength}, self.target, self:GetAbility():GetCaster():GetTeam(), false)
	end
end

---

LinkLuaModifier("modifier_singularity_charging_thinker", "heroes/enigma/singularity", LUA_MODIFIER_MOTION_NONE)
modifier_singularity_charging_thinker = class({})

---

LinkLuaModifier("modifier_singularity_thinker", "heroes/enigma/singularity", LUA_MODIFIER_MOTION_NONE)
modifier_singularity_thinker = class({})

function modifier_singularity_thinker:OnCreated(info)
	if not IsServer() then return end
	self.strength = info.strength
	self.ability = self:GetAbility()
	self.caster = self.ability:GetCaster()
	self.team = self.caster:GetTeam()
	self.parent = self:GetParent()
	self.location = self.parent:GetAbsOrigin()
	self.pull_radius = self.ability:GetSpecialValueFor("pull_radius")
	self.max_pull = 300 * self.strength
	--self.max_pull = self.ability:GetSpecialValueFor("max_pull") * self.strength
	self.stun_time = self.ability:GetSpecialValueFor("max_stun") * self.strength
	self.damage = self.ability:GetSpecialValueFor("max_damage") * self.strength
	self.damage_radius = 50

	self.damaged_units = {}
	self.velocities = {}

	StartSoundEvent("Hero_Enigma.Black_Hole", self.parent)

	GridNav:DestroyTreesAroundPoint(self.location, self.pull_radius, false)

	self.tick_rate = 0.1
	self:StartIntervalThink(self.tick_rate)
end

function modifier_singularity_thinker:OnIntervalThink()
	-- Pull units
	local units = FindUnitsInRadius(self.team, self.location, nil, self.pull_radius, DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, 0, 0, false)
	for k,unit in pairs(units) do
		if not self.damaged_units[unit] and not unit:IsInvulnerable() then
			-- Calculate velocity
			local unit_origin = unit:GetAbsOrigin()
			local direction = ((self.location - unit_origin) * Vector(1,1,0)):Normalized()
			local distance = DistanceBetweenVectors(self.location, unit_origin)
			-- Speed depends on how far from the center they are
			local speed = (self.pull_radius - distance) / self.pull_radius * self.max_pull
			local velocity = speed * direction
			-- Adjust this based on the velocity we saved from the previous tick
			if self.velocities[unit] then
				velocity = velocity - self.velocities[unit]
			end

			-- Apply physics
			if not IsPhysicsUnit(unit) then
				Physics:Unit(unit)
			end

			unit:AddPhysicsVelocity(velocity)
			self.velocities[unit] = velocity
		end
	end

	-- Damage units that have reached the center
	units = FindUnitsInRadius(self.team, self.location, nil, self.damage_radius, DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, 0, 0, false)
	for k,unit in pairs(units) do
		-- Make sure we haven't already hit them
		if not self.damaged_units[unit] and not unit:IsInvulnerable() then
			self.damaged_units[unit] = true
			ApplyDamage({
				damage = self.damage,
				damage_type = DAMAGE_TYPE_MAGICAL,
				attacker = self.caster,
				victim = unit,
				ability = self.ability,
			})
			unit:AddNewModifier(self.caster, self.ability, "modifier_stunned", {duration = self.stun_time})
			unit:SetPhysicsVelocity(Vector(0,0,0))
			unit:EmitSound("Hero_Sven.StormBoltImpact")
		end
	end
end

function modifier_singularity_thinker:OnDestroy()
	if not IsServer() then return end
	StopSoundEvent("Hero_Enigma.Black_Hole", self.parent)
	StartSoundEvent("Hero_Enigma.Black_Hole.Stop", self.parent)
end

function modifier_singularity_thinker:GetEffectName()
	return "particles/units/heroes/hero_enigma/enigma_blackhole.vpcf"
end

function modifier_singularity_thinker:GetEffectAttachType()
	return PATTACH_ABSORIGIN_FOLLOW
end

---

collapse_singularity = class({})

function collapse_singularity:OnSpellStart()
	if self:GetCaster():HasModifier("modifier_singularity_charging") then
		self:GetCaster():RemoveModifierByName("modifier_singularity_charging")
	end
end