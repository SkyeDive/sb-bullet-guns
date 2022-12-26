require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Base gun fire ability
GunFireAmmo = WeaponAbility:new()

function GunFireAmmo:init()
  self.weapon:setStance(self.stances.idle)

  self.cooldownTimer = self.fireTime

  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end
end

local function specialConsumeTaggedItem(sTag)
  local taggedItems = player.itemsWithTag(sTag)
  local consumedItem = nil
  for k,v in ipairs(taggedItems) do --Loop here on the off chance it would return an invalid item
    consumedItem = player.consumeItem(v.name)
	if consumedItem then break end
  end
  return consumedItem
end

function GunFireAmmo:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  if animator.animationState("firing") ~= "fire" then
    animator.setLightActive("muzzleFlash", false)
  end

  if self.fireMode == (self.activatingFireMode or self.abilitySlot)
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    --[[and not status.resourceLocked("energy")]] --We don't need this anymore; we're only using items
    and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then

--In essence, I just replaced the "return true if able to use up energy" part with "return true if able to use up item"
--I added a section to the weapon called "ammoItemTag" which is the tag of the item(s), in my case the tag "example" for the items "bullet" and "pellet"
--It'll therefore check the inventory for items with the tag, consume one if they exist, and return true so the gun will shoot


	if self.fireType == "auto" then --New code starts here
		self.bulletConsumed = specialConsumeTaggedItem(self.ammoItemTag) --This both checks the inventory for items with the tag AND consumes one if one exists
		if self.bulletConsumed then --Additionally, this method should (though I've never seen it fail) try to consume items starting from the first slot sequentially
			self:setState(self.auto) --In order words, it'll check slot 1, then 2, then 3, then so on until it reaches a valid item or the end of the inventory
		end
	elseif self.fireType == "burst" then
	  self:setState(self.burst)
	end
  end
end

function GunFireAmmo:auto()
  self.weapon:setStance(self.stances.fire)

  self:fireProjectile()
  self:muzzleFlash()

  if self.stances.fire.duration then
    util.wait(self.stances.fire.duration)
  end

  self.cooldownTimer = self.fireTime
  self:setState(self.cooldown)
end

function GunFireAmmo:burst()
  self.weapon:setStance(self.stances.fire)

  local shots = self.burstCount
  
  --while shots > 0 and status.overConsumeResource("energy", self:energyPerShot()) do --This is the original line of code
  while shots > 0 do --This line and the next two are the new code
	self.bulletConsumed = specialConsumeTaggedItem(self.ammoItemTag)
	if self.bulletConsumed == nil then break end --Breaks the while loop for burst fire if there aren't any items left to use
	
    self:fireProjectile()
    self:muzzleFlash()
    shots = shots - 1

    self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.weaponRotation))
    self.weapon.relativeArmRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.armRotation))

    util.wait(self.burstTime)
  end

  self.cooldownTimer = (self.fireTime - self.burstTime) * self.burstCount
end

function GunFireAmmo:cooldown()
  self.weapon:setStance(self.stances.cooldown)
  self.weapon:updateAim()

  local progress = 0
  util.wait(self.stances.cooldown.duration, function()
    local from = self.stances.cooldown.weaponOffset or {0,0}
    local to = self.stances.idle.weaponOffset or {0,0}
    self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

    self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.weaponRotation, self.stances.idle.weaponRotation))
    self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.armRotation, self.stances.idle.armRotation))

    progress = math.min(1.0, progress + (self.dt / self.stances.cooldown.duration))
  end)
end

function GunFireAmmo:muzzleFlash()
  animator.setPartTag("muzzleFlash", "variant", math.random(1, self.muzzleFlashVariants or 3))
  animator.setAnimationState("firing", "fire")
  animator.burstParticleEmitter("muzzleFlash")
  animator.playSound("fire")

  animator.setLightActive("muzzleFlash", true)
end

function GunFireAmmo:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
  --First we grab the JSON of the item
  local bulletConfig = root.itemConfig(self.bulletConsumed).config
  local params = sb.jsonMerge(self.projectileParameters, projectileParams or {})
  --Then we add the additional damage per shot from the item to the damage to be dealt
  params.power = self:damagePerShot() + (bulletConfig.ammunitionDamage or 0) --"or 0" is included in case the additional damage is not defined
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.speed = util.randomInRange(params.speed)

  if not projectileType then
	--Finally we set the projectile to the one specified in the item's JSON, falling back on the gun's projectile if one does not exist
    projectileType = bulletConfig.projectileType or self.projectileType
  end
  if type(projectileType) == "table" then
    projectileType = projectileType[math.random(#projectileType)]
  end

  local projectileId = 0
  for i = 1, (projectileCount or self.projectileCount) do
    if params.timeToLive then
      params.timeToLive = util.randomInRange(params.timeToLive)
    end

    projectileId = world.spawnProjectile(
        projectileType,
        firePosition or self:firePosition(),
        activeItem.ownerEntityId(),
        self:aimVector(inaccuracy or self.inaccuracy),
        false,
        params
      )
  end
  return projectileId
end

function GunFireAmmo:firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
end

function GunFireAmmo:aimVector(inaccuracy)
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()
  return aimVector
end

--[[function GunFireAmmo:energyPerShot()
  return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end]]-- This function was removed because it will never be used here

function GunFireAmmo:damagePerShot()
  return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function GunFireAmmo:uninit()
end
