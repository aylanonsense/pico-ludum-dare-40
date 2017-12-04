pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- curse collector
-- by ayla myers (aka bridgs)

--[[
hurtbox channels
	1: player
	2: witch
	4: minions
	8: tombstones
	16: fences
	32: heart

obstacle channels
	1: player
	2: tombstones
	4: trees
	8: minions
	16: fences
]]

-- useful no-op function
function noop() end

-- global collision vars
local directions={"right","up","down","left"}
local direction_attrs={
	-- direction_name,axis,size,increment
	{"left","x","vx","width",-1},
	{"right","x","vx","width",1},
	{"bottom","y","vy","height",-1},
	{"top","y","vy","height",1}
}
local clockwise_dirs={
	left="up",
	up="right",
	right="down",
	down="left"
}

-- global scene vars
local scenes
local scene
local scene_frame
local freeze_frames
local screen_shake_frames

-- global input vars
local buttons={}
local button_presses={}

-- global entity vars
local entities
local new_entities
local player
local player2

-- global list of curses
local player_curses
local curses={
	{"axes","unreliable weapon",{"your attacks spin around","you in a circle."}},
	{"shadow","stalked by shadows",{"a malicious shadow","follows behind you."}},
	{"love","misplaced affection",{"you occasionally fall in","love with minions. it hurts you to","see them get hurt."}},
	{"slippery","eternal slipperiness",{"you slide along the ground."}},
	{"lonely","crippling loneliness",{"you slowly take damage","unless you stay near","another creature."}},
	{"big-heart","big heart",{"you have a very","big heart."}},
	{"magnetic","magnetic",{"metallic objects are","attracted to you."}},
	{"floating-heart","heart on your sleeve",{"a heart circles around you.", "if you attack it,","you take damage."}},
	{"monochrome","colorblind",{"you can't distinguiush","between colors."}},
	{"medium","reluctant medium",{"whenever you destroy a","tombstone you raise","a skeleton."}},
	{"doppleganger","doppleganger",{"there are two of you."}},
	{"slow-clear","constant daze",{"the world swirls around you."}},
	{"crab-walk","crab-like tendencies",{"you walk and","attack sideways."}},
	{"weakness","weakness",{"your attacks deal","less damage."}},
	{"frog-summons","amphibian attraction",{"whenever you attack","you summon a frog."}},
	{"threes","threes",{"you attack in threes."}},
	{"hallucinations","hallucinations",{"you see things","that aren't there."}},
	{"vertigo","extreme vertigo",{"you are constantly dizzy."}},
	{"gigantic","excessive growth",{"you are twice as big and","move at half speed."}},
	{"tele-on-hit","unstable structure",{"whenever you take damage","you teleport to a","random location."}},
	{"near-sighted","clouded eyes",{"your eyesight is limited."}},
	{"invisibility","hidden from mortal eyes",{"you are invisible."}},
	{"perma-move","eternal unrest",{"you can't stop moving."}},
	{"high-speed","ludicrous speed",{"you move 5x faster than normal."}},
	{"no-left","sinistrophobia",{"you can't turn left."}},
}

-- entity classes
local entity_classes={
	player={
		width=7,
		height=7,
		health=3,
		obstacle_channel=1, -- player
		collision_channel=1+2+4+16, -- player + tombstones + trees + fences
		facing_dir="right",
		true_facing_dir="right",
		move_dir=nil,
		sword_attack_anim=0,
		sword_attack_cooldown=0,
		javelin_throw_anim=0,
		javelin_throw_cooldown=0,
		dodge_roll_dir=nil,
		dodge_roll_anim=0,
		dodge_roll_end_anim=0,
		dodge_roll_detection=5,
		frames_to_loneliness=0,
		frames_to_love=0,
		weapons={"sword","javelin"},
		weapon_index=1,
		keep_in_bounds=true,
		auto_attacks=0,
		init=function(self)
			if player_has_curse("gigantic") then
				self.width*=2
				self.height*=2
			end
			if player_has_curse("lonely") then
				self.frames_to_loneliness=149
			end
			if player_has_curse("love") then
				self.frames_to_love=rnd_int(100,400)
			end
		end,
		update=function(self)
			if decrement_counter_prop(self,"frames_to_loneliness") then
				self.health-=1
				if self:on_hurt(e1)!=false and self.health<=0 then
					self:die()
				end
				self.frames_to_loneliness=149
			end
			local i
			for i=1,#entities do
				if entities[i].class_name=="frog" or entities[i].class_name=="bat" or entities[i].class_name=="skeleton" or entities[i].class_name=="witch" then
					local dx=mid(-100,entities[i]:center_x()-self:center_x(),100)
					local dy=mid(-100,entities[i]:center_y()-self:center_y(),100)
					local dist=sqrt(dx*dx+dy*dy)
					if dist<30 then
						self.frames_to_loneliness=150
					end
				end
			end
			if decrement_counter_prop(self,"frames_to_love") then
				local i
				local suitors={}
				for i=1,#entities do
					if entities[i].class_name=="frog" or entities[i].class_name=="skeleton" then
						add(suitors,entities[i])
					end
				end
				if #suitors>0 then
					spawn_entity("in_love",0,0,{target=suitors[rnd_int(1,#suitors)]})
				end
				self.frames_to_love=rnd_int(200,400)
			end
			decrement_counter_prop(self,"sword_attack_anim")
			decrement_counter_prop(self,"sword_attack_cooldown")
			decrement_counter_prop(self,"javelin_throw_anim")
			decrement_counter_prop(self,"javelin_throw_cooldown")
			decrement_counter_prop(self,"dodge_roll_end_anim")
			if decrement_counter_prop(self,"dodge_roll_anim") then
				self.dodge_roll_end_anim=10
				self.move_dir=nil
			end
			if decrement_counter_prop(self,"dodge_roll_detection") then
				self.dodge_roll_dir=nil
			end
			self.hurtbox_channel=ternary(self.dodge_roll_anim>0,0,1) -- player
			-- switch move direction when a button pressed
			if self.dodge_roll_end_anim<=0 and self.sword_attack_anim<=0 and self.javelin_throw_anim<=0 then
				foreach(directions,function(dir)
					if self.dodge_roll_anim<=0 and btnp2(dir) then
						if not player_has_curse("no-left") or self.facing_dir==dir or dir==clockwise_dirs[self.facing_dir] then
							self.move_dir=dir
							-- if dir==self.dodge_roll_dir then
							-- 	self.dodge_roll_anim=8
							-- else
							-- 	self.dodge_roll_detection=8
							-- 	self.dodge_roll_dir=dir
							-- end
						end
					end
				end)
				if self.dodge_roll_anim<=0 then
					-- stop moving when the button is released
					if self.move_dir and not btn2(self.move_dir) then
						self.move_dir=nil
					end
					-- switch move direction to a held button
					if not self.move_dir then
						foreach(directions,function(dir)
							if btn2(dir) then
								if not player_has_curse("no-left") or self.facing_dir==dir or dir==clockwise_dirs[self.facing_dir] then
									self.move_dir=dir
								end
							end
						end)
					end
				end
			end
			-- no moving during an animation
			local move_speed=1
			if player_has_curse("gigantic") then
				move_speed*=0.5
			end
			if player_has_curse("high-speed") then
				move_speed*=5
			end
			local vx,vy=0,0
			if self.javelin_throw_anim>0 or self.sword_attack_anim>0 or self.dodge_roll_end_anim>0 or self.auto_attacks>0 then
				vx,vx=0,0
			else
				-- face the direction of movement
				if self.move_dir then
					self.facing_dir=self.move_dir
					if player_has_curse("crab-walk") then
						self.true_facing_dir=clockwise_dirs[self.facing_dir]
					else
						self.true_facing_dir=self.facing_dir
					end
				end
				-- move in the movement direction
				local move_dir=self.move_dir
				if player_has_curse("perma-move") then
					move_dir=move_dir or self.facing_dir
				end
				vx,vy=dir_to_vector(move_dir,move_speed*ternary(self.dodge_roll_anim>0,2.5,1))
			end
			if player_has_curse("slippery") then
				self.vx=mid(-1.2*move_speed,(self.vx+vx/20)*0.995,1.2*move_speed)
				self.vy=mid(-1.2*move_speed,(self.vy+vy/20)*0.995,1.2*move_speed)
			else
				self.vx=vx
				self.vy=vy
			end
			-- move the character
			self:apply_velocity()
			-- switch weapons
			-- if btnp2("x") then
			-- 	self.weapon_index=1+(self.weapon_index%#self.weapons)
			-- end
			-- throw a javelin
			if self.dodge_roll_anim<=0 and self.dodge_roll_end_anim<=0 and btnp2("z") or self.auto_attacks>0 then
				if self.weapons[self.weapon_index]=="sword" and self.sword_attack_cooldown<=0 then
					self.sword_attack_anim=10*ternary(player_has_curse("gigantic"),2,1)
					self.sword_attack_cooldown=10*ternary(player_has_curse("gigantic"),2,1)+7
					if player_has_curse("threes") and self.auto_attacks==0 then
						self.auto_attacks=2
					else
						decrement_counter_prop(self,"auto_attacks")
					end
					if player_has_curse("frog-summons") then
						local x=rnd_int(20,100)
						local y=0
						if rnd()<0.5 then
							y=75
						end
						spawn_entity("frog",x,y)
					end
					if player_has_curse("axes") then
						spawn_entity("axe_attack",self.x,self.y,{attack_dir=self.true_facing_dir})
					else
						spawn_entity("sword_attack",self.x,self.y,{slash_dir=self.true_facing_dir})
					end
				elseif self.weapons[self.weapon_index]=="javelin" and self.javelin_throw_cooldown<=0 then
					self.javelin_throw_anim=10
					self.javelin_throw_cooldown=30
					spawn_entity("javelin",self.x+2,self.y+2,{move_dir=self.true_facing_dir})
				end
			end
		end,
		draw=function(self)
			if player_has_curse("lonely") then
				color(ternary(self.frames_to_loneliness==150,3,1))
				if player_has_curse("monochrome") then
					color(ternary(self.frames_to_loneliness==150,14,2))
				end
				circ(self:center_x(),self:center_y(),30)
				circ(self:center_x(),self:center_y(),30*self.frames_to_loneliness/150)
			end
			local sx
			local sy=11
			local sw=7
			local sh=12
			local sflipped=(self.true_facing_dir=="left")
			local sdx=0
			local sdy=5
			if self.true_facing_dir=="down" then
				sx=57
			elseif self.true_facing_dir=="up" then
				sx=105
			else
				sx=81
			end
			if self.dodge_roll_anim>0 then
				sx+=ternary(self.dodge_roll_anim>4,8,16)
				sy=24
				sh=7
				sdy=0
			elseif self.vx!=0 or self.vy!=0 then
				sx+=ternary(self.frames_alive%16>8,8,16)
			end
			if self.sword_attack_anim>0 then
				if self.true_facing_dir=="down" then
					sx,sy,sw,sh,sdy=23,14,6,17,4
				elseif self.true_facing_dir=="up" then
					sx,sy,sw,sh,sdy=30,7,7,20,13
				else
					sx,sh,sw,sh,sdx,sdy=38,15,18,12,ternary(self.true_facing_dir=="left",11,0),8
				end
			end
			if self.invincibility_frames%6<3 then
				if player_has_curse("invisibility") then
					local i
					for i=0,15 do
						palt(i,true)
					end
				end
				pal(3,10)
				palt(3,false)
				pal(11,7)
				palt(11,false)
				pal(12,10)
				if player_has_curse("monochrome") then
					pal(3,15)
					pal(10,15)
					pal(11,15)
					pal(9,14)
					pal(4,13)
					pal(12,15)
				end
				if self.is_shadow then
					local i
					for i=1,15 do
						pal(i,ternary(player_has_curse("monochrome"),2,1))
					end
				end
				local size_mult=ternary(player_has_curse("gigantic"),2,1)
				if player_has_curse("axes") then
					palt(3,true)
					palt(11,true)
					pal(12,9)
					if player_has_curse("monochrome") then
						pal(12,14)
					end
				end
				sspr2(sx,sy,sw,sh,self.x-size_mult*sdx,self.y-size_mult*sdy,sflipped,false,size_mult*sw,size_mult*sh)
				-- self:draw_outline(12)
			end
		end,
		on_death=function(self)
			init_scene("death")
		end,
		on_hurt=function(self)
			self:hurt()
		end,
		hurt=function(self)
			self.invincibility_frames=48
			if player2 then
				player.invincibility_frames=48
				player2.invincibility_frames=48
				player.health=min(player.health,player2.health)
				player2.health=min(player.health,player2.health)
			end
			freeze_and_shake_screen(6,10)
			if player_has_curse('tele-on-hit') then
				self.x=rnd_int(0,112)
				self.y=rnd_int(0,68)
			end
		end
	},
	player_shadow={
		extends="player",
		hitbox_channel=1, -- player
		hurtbox_channel=0,
		obstacle_channel=0,
		collision_channel=0,
		x=-20,
		y=-20,
		keep_in_bounds=false,
		is_shadow=true,
		init=function(self)
			self.player_states={}
		end,
		update=function(self)
			if self.player_states[1] then
				self:apply_player_state(self.player_states[1])
			end
			local i
			for i=1,59 do
				self.player_states[i]=self.player_states[i+1]
			end
			self.player_states[60]=self:copy_player_state()
		end,
		apply_player_state=function(self,state)
			local k,v
			for k,v in pairs(state) do
				self[k]=state[k]
			end
		end,
		copy_player_state=function(self)
			return {
				x=player.x,
				y=player.y,
				vx=player.vx,
				vy=player.vy,
				facing_dir=player.facing_dir,
				true_facing_dir=player.true_facing_dir,
				move_dir=player.move_dir,
				sword_attack_anim=player.sword_attack_anim,
				sword_attack_cooldown=player.sword_attack_cooldown,
				frames_alive=player.frames_alive
			}
		end
	},
	axe_attack={
		width=5,
		height=5,
		frames_to_death=100,
		hitbox_channel=2+4+8+16+32, -- witches + minions + tombstones + fences + heart
		collision_channel=16, -- trees
		init=function(self)
			self.x+=1
			self.y+=1
			self.scale=1
			if player_has_curse("gigantic") then
				self.scale=2
				self.width*=2
				self.height*=2
			end
			self.start_x=self.x
			self.start_y=self.y
			if self.attack_dir=="right" then
				self.offset=0
			elseif self.attack_dir=="left" then
				self.offset=20
			elseif self.attack_dir=="up" then
				self.offset=10
			elseif self.attack_dir=="down" then
				self.offset=30
			end
		end,
		update=function(self)
			self.x=self.start_x+(self.scale*6+self.frames_alive/3)*cos((self.frames_alive+self.offset)/40)
			self.y=self.start_y+(self.scale*6+self.frames_alive/3)*sin((self.frames_alive+self.offset)/40)
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(7,15)
				pal(10,15)
				pal(9,14)
			end
			sspr2(0,57,5,5,self.x,self.y,self.frames_alive%12>6,(self.frames_alive+3)%12>6,5*self.scale,5*self.scale)
			-- self:draw_outline(8)
		end,
		on_hit=function(self)
			self:die()
		end,
		on_collide=function(self)
			self:die()
		end
	},
	in_love={
		init=function(self)
			self.prev_health=self.target.health
		end,
		update=function(self)
			self.x=self.target:center_x()
			self.y=self.target:center_y()
			if not self.target.is_alive then
				hurt_entity(player)
				self:die()
			elseif self.prev_health>self.target.health then
				hurt_entity(player)
			end
			self.prev_health=self.target.health
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(8,14)
				pal(14,15)
			end
			sspr(0,53,5,4,self.x-3,self.y-11)
		end
	},
	floating_heart={
		width=4,
		height=4,
		hurtbox_channel=32, -- heart
		update=function(self)
			self.x=player.x+10*cos(self.frames_alive/100)
			self.y=player.y+10*sin(self.frames_alive/100)
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(8,14)
				pal(14,15)
			end
			sspr(0,53,5,4,self.x,self.y)
			-- self:draw_outline(7)
		end,
		on_hurt=function(self)
			hurt_entity(player,self)
			return false
		end
	},
	sword_attack={
		width=15,
		height=7,
		frames_to_death=1,
		hitbox_channel=2+4+8+16+32, -- witches + minions + tombstones + fences + heart
		init=function(self)
			local size_mult=ternary(player_has_curse("gigantic"),2,1)
			if self.slash_dir=="right" then
				self.x+=size_mult*2
			elseif self.slash_dir=="left" then
				self.x-=size_mult*10
			else
				self.width,self.height=7,12
				if self.slash_dir=="down" then
					self.y+=size_mult*1
				else
					self.y-=size_mult*9
				end
			end
			self.width*=size_mult
			self.height*=size_mult
		end,
		draw=noop,
		on_hit=function(self)
			freeze_and_shake_screen(1,2)
		end
	},
	javelin={
		width=5,
		height=5,
		hitbox_channel=2+4+8, -- witches + minions + tombstones
		collision_channel=4+16, -- trees + fences
		update=function(self)
			self.vx,self.vy=dir_to_vector(self.move_dir,2)
			self:apply_velocity()
		end,
		draw=function(self)
			local x,y=self.x,self.y-1
			self:draw_outline(8)
			if self.move_dir=="up" then
				sspr2(0,7,3,11,x+1,y,true)
			elseif self.move_dir=="down" then
				sspr2(0,7,3,11,x+1,y-6)
			elseif self.move_dir=="left" then
				sspr2(3,7,11,3,x,y)
			elseif self.move_dir=="right" then
				sspr2(3,7,11,3,x-6,y,true)
			end
		end,
		on_hit=function(self)
			self:die()
		end,
		on_collide=function(self)
			self:die()
		end
	},
	witch={
		width=10,
		height=8,
		health=2,
		hitbox_channel=1, -- player
		hurtbox_channel=2, -- witch
		spell=nil,
		spell_startup_frames=0,
		spell_recovery_frames=0,
		spell_cooldown_frames=20,
		keep_in_bounds=true,
		update=function(self)
			-- start casting a spell
			if decrement_counter_prop(self,"spell_cooldown_frames") then
				local spells={"summon_frogs","lob_blasts","shoot_bats","raise_skeletons"}
				self.spell=spells[rnd_int(1,#spells)]
				self.spell_startup_frames=40
			end
			-- cast a spell
			if decrement_counter_prop(self,"spell_startup_frames") then
				if self.spell=="shoot_bats" then
					spawn_entity("bat",self.x-2,self.y,{wait_frames=1})
					spawn_entity("bat",self.x-2,self.y,{wait_frames=10})
					spawn_entity("bat",self.x-2,self.y,{wait_frames=20})
				elseif self.spell=="summon_frogs" then
					spawn_entity("frog",self.x-5,self.y-4)
					spawn_entity("frog",self.x-5,self.y+4)
				elseif self.spell=="lob_blasts" then
					local i
					for i=1,3 do
						spawn_entity("lobbed_bomb",self.x,self.y,{target_x=player.x+rnd_int(-14,14),target_y=player.y+rnd_int(-10,10)})
					end
				elseif self.spell=="raise_skeletons" then
					spawn_entity("skeleton",self.x-5,self.y)
				end
				self.spell_recovery_frames=30
			end
			-- cooldown between spell casts
			if decrement_counter_prop(self,"spell_recovery_frames") then
				self.spell_cooldown_frames=rnd_int(60,120)
			end
			self:apply_velocity()
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(5,2)
				pal(4,14)
				pal(7,15)
				pal(3,2)
			end
			if self.spell_startup_frames>0 then
				if self.spell=="shoot_bats" then
					color(13)
				elseif self.spell=="summon_frogs" then
					color(3)
				elseif self.spell=="lob_blasts" then
					color(14)
				elseif self.spell=="raise_skeletons" then
					color(7)
				end
				circ(self.x,self.y,self.spell_startup_frames/2)
			end
			sspr2(ternary(self.spell_startup_frames>0 or self.spell_recovery_frames>0,96,86),0,10,11,self.x,self.y-3)
		end,
		on_death=function(self)
			init_scene("curse")
		end
	},
	bat={
		width=5,
		height=5,
		hitbox_channel=1, -- player
		hurtbox_channel=4, -- minion
		frames_to_death=70,
		update=function(self)
			if decrement_counter_prop(self,"wait_frames") then
				local dx=mid(-100,player:center_x()-self:center_x(),100)
				local dy=mid(-100,player:center_y()-self:center_y(),100)
				local dist=sqrt(dx*dx+dy*dy)
				self.vx=1.2*dx/dist
				self.vy=1.2*dy/dist
			end
			self.vx*=1.03
			self.vy*=1.03
			self:apply_velocity()
		end,
		draw=function(self)
			if self.wait_frames<=0 then
				-- self:draw_outline()
				if player_has_curse("monochrome") then
					pal(7,15)
					pal(8,14)
					pal(1,2)
				end
				sspr2(ternary(self.frames_alive%8>4,6,0),36,6,5,self.x-1,self.y)
			end
		end
	},
	lobbed_bomb={
		frames_to_death=40,
		init=function(self)
			self.vx=(self.target_x-self.x)/40
			self.vy=(self.target_y-self.y)/40
		end,
		update=function(self)
			if self.frames_alive==40 then
				self.vx,self.vy=0,0
			end
			self:apply_velocity()
		end,
		draw=function(self)
			local f=self.frames_alive
			local x=self.x
			local y=self.y+0.076*f*f-3*f
			circfill(x,y,3,14)
			pset(self.target_x,self.target_y,14)
		end,
		on_death=function(self)
			spawn_entity("explosion",self.x-4,self.y-4)
		end
	},
	explosion={
		width=8,
		height=8,
		hitbox_channel=1+4+8+16, -- player + minions + tombstones + fences
		frames_to_death=4,
		draw=function(self)
			circfill(self.x+4.5,self.y+4.5,4,7)
		end
	},
	frog={
		width=7,
		height=6,
		health=1,
		hitbox_channel=1, -- player
		hurtbox_channel=4, -- minion
		obstacle_channel=8, -- minion
		collision_channel=2+4+8+16, -- tombstones + trees + minions + fences
		hop_frames=0,
		frames_to_hop=1,
		keep_in_bounds=true,
		update=function(self)
			decrement_counter_prop(self,"hop_frames")
			if decrement_counter_prop(self,"frames_to_hop") then
				local dx=mid(-100,player:center_x()-self:center_x(),100)
				local dy=mid(-100,player:center_y()-self:center_y(),100)
				local dist=sqrt(dx*dx+dy*dy)
				self.vx,self.vy=dx/dist,dy/dist
				self.frames_to_hop=rnd_int(35,60)
				self.hop_frames=rnd_int(8,12)
				self.is_facing_right=self.vx>0
			end
			if self.hop_frames<=0 then
				self.vx,self.vy=0,0
			end
			self:apply_velocity()
		end,
		draw=function(self)
			-- self:draw_outline(8)
			if player_has_curse("monochrome") then
				pal(11,14)
				pal(3,2)
			end
			sspr2(ternary(self.hop_frames>0,31,22),0,9,6,self.x-1,self.y,self.is_facing_right)
		end
	},
	skeleton={
		width=7,
		height=9,
		health=2,
		hitbox_channel=1, -- player
		hurtbox_channel=4, -- minion
		obstacle_channel=8, -- minion
		collision_channel=2+4+8+16, -- tombstones + trees + minions + fences
		keep_in_bounds=true,
		update=function(self)
			-- decrement_counter_prop(self,"hop_frames")
			-- if decrement_counter_prop(self,"frames_to_hop") then
			local dx=mid(-100,player:center_x()-self:center_x(),100)
			local dy=mid(-100,player:center_y()-self:center_y(),100)
			local dist=sqrt(dx*dx+dy*dy)
			if dist<40 then
				self.vx,self.vy=0.5*dx/dist,0.5*dy/dist
			elseif self.frames_alive%30==0 then
				local angle=rnd()
				self.vx,self.vy=0.5*cos(angle),0.5*sin(angle)
			elseif self.frames_alive%30==20 then
				self.vx,self.vy=0,0
			end
			self:apply_velocity()
			-- 	self.frames_to_hop=rnd_int(35,60)
			-- 	self.hop_frames=rnd_int(8,12)
			-- 	self.is_facing_right=self.vx>0
			-- end
			-- if self.hop_frames<=0 then
			-- 	self.vx,self.vy=0,0
			-- end
			-- self:apply_velocity()
		end,
		draw=function(self)
			-- self:draw_outline(8)
			if player_has_curse("monochrome") then
				pal(7,15)
				pal(6,15)
			end
			sspr2(ternary(self.frames_alive%14>7,0,8),42,7,11,self.x,self.y-2,self.is_facing_right)
		end,
		on_hurt=function(self)
			self.x-=20*self.vx
			self.y-=20*self.vy
		end
	},
	tombstone={
		width=6,
		height=6,
		health=2,
		hurtbox_channel=8, -- tombstone
		obstacle_channel=2, -- tombstone
		init=function(self)
			self.flipped=rnd()<0.5
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(1,2)
				pal(6,14)
			end
			sspr2(12,0,10,6,self.x-2,self.y+2,self.flipped)
			sspr2(ternary(self.health<2,6,0),0,6,7,self.x,self.y-1)
		end,
		on_death=function(self)
			if player_has_curse("medium") then
				spawn_entity("skeleton",self.x,self.y)
			end
		end
	},
	tree={
		width=10,
		height=9,
		obstacle_channel=4, -- tree
		draw=function(self)
			-- rectfill(self.x+0.5,self.y-7.5,self.x+10.5,self.y+9.5,4)
			-- self:draw_outline(9)
			if player_has_curse("monochrome") then
				pal(4,14)
			end
			sspr2(0,18,19,17,self.x-4,self.y-7)
		end
	},
	horizontal_fence={
		width=9,
		height=4,
		health=2,
		hurtbox_channel=16, -- fence
		obstacle_channel=16, -- fence
		collision_channel=16, -- fence
		update=function(self)
			if player_has_curse("magnetic") then
				local dx=mid(-100,player:center_x()-self:center_x(),100)
				local dy=mid(-100,player:center_y()-self:center_y(),100)
				local dist=sqrt(dx*dx+dy*dy)
				if dist<50 and dist>10 then
					self.vx=0.25*dx/dist
					self.vy=0.25*dy/dist
				else
					self.vx=0
					self.vy=0
				end
			else
			end
			self:apply_velocity()
		end,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(5,13)
			end
			sspr(ternary(self.health<2,51,40),0,11,7,self.x-1,self.y-3)
		end
	},
	vertical_fence={
		extends="horizontal_fence",
		width=3,
		height=7,
		draw=function(self)
			if player_has_curse("monochrome") then
				pal(5,13)
			end
			sspr(ternary(self.health<2,65,62),0,3,7,self.x,self.y-1)
		end
	}
}

-- basic pico-8 methods
function _init()
	-- set up the scenes
	scenes={
		title={init_title,update_title,draw_title},
		game={init_game,update_game,draw_game},
		curse={init_curse,update_curse,draw_curse},
		death={init_death,update_death,draw_death}
	}
	-- initialize the starting scene
	init_scene("title")
	init_scene("game")
end

function _update()
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
	else
		screen_shake_frames=decrement_counter(screen_shake_frames)
		scene_frame=increment_counter(scene_frame)
		-- keep track of when inputs are pressed
		local i
		for i=0,5 do
			button_presses[i]=btn(i) and not buttons[i]
			buttons[i]=btn(i)
		end
		-- update scene
		scene[2]()
	end
end

function _draw()
	local shake_x=0
	if screen_shake_frames>0 then
		shake_x=mid(1,screen_shake_frames/2,3)*(2*(scene_frame%2)-1)
	end
	-- clear the screen
	camera()
	if player_has_curse("slow-clear") then
		local i=0
		for i=1,1000 do
			pset(rnd_int(0,127),rnd_int(0,127),0)
		end
	else
		cls(0)
	end
	-- draw guidelines
	-- rect(0,0,127,127,1)
	-- rect(2,25,125,102,1)
	-- rect(63,0,64,127,1)
	-- draw scene
	scene[3](shake_x)
end

-- title scene methods
function init_title()
	player_curses={}
	-- debug_add_curse(curses[1][1])
	-- debug_add_curse("axes")
	-- debug_add_curse("monochrome")
	shuffle_list(curses)
end

function update_title()
	if scene_frame>20 and btnp2("z") then
		init_scene("game")
	end
end

function draw_title()
	color(13)
	if scene_frame%40<30 then
		print("press z to continue",26,108)
	end
end

-- game scene methods
function init_game()
	-- reset vars
	entities={}
	new_entities={}
	-- create initial entities
	generate_level()
	-- spawn_entity("tombstone",70,60)
	-- spawn_entity("tree",60,80)
	-- spawn_entity("frog",80,80)
	-- spawn_entity("frog",90,80)
	-- spawn_entity("frog",90,90)
	-- spawn_entity("frog",80,90)
	-- spawn_entity("horizontal_fence",30,40+28)
	-- spawn_entity("horizontal_fence",38,40+28)
	-- spawn_entity("horizontal_fence",46,40+28)
	-- spawn_entity("vertical_fence",29,45)
	-- spawn_entity("vertical_fence",29,52)
	-- spawn_entity("vertical_fence",29,59)
	-- spawn_entity("horizontal_fence",30,40)
	-- spawn_entity("horizontal_fence",38,40)
	-- spawn_entity("horizontal_fence",46,40)
	if player_has_curse("hallucinations") then
		local possibilities={"player","witch","skeleton","frog","tombstone","tree","horizontal_fence","vertical_fence"}
		local i
		for i=1,10 do
			spawn_entity(possibilities[rnd_int(1,#possibilities)],rnd_int(10,100),rnd_int(10,70),{is_hallucination=true})
		end
	end
	-- add new entities to the game immediately
	add_new_entities()
end

function generate_level()
	local tiles={}
	local c,r
	for c=1,16 do
		tiles[c]={}
	end
	-- spawn the player
	local player_col=1
	local player_row=6
	player=spawn_entity("player",8*player_col-7,7*player_row-7)
	if player_has_curse("floating-heart") then
		spawn_entity("floating_heart")
	end
	if player_has_curse("shadow") then
		spawn_entity("player_shadow")
	end
	tiles[player_col][player_row]=player
	if player_has_curse("doppleganger") then
		local player2_col=1
		local player2_row=7
		player2=spawn_entity("player",8*player2_col-7,7*player2_row-7)
		tiles[player2_col][player2_row]=player2
	else
		player2=nil
	end
	-- spawn the witch
	local witch_col=rnd_int(14,15)
	local witch_row=rnd_int(4,8)
	local witch=spawn_entity("witch",8*witch_col-9,7*witch_row-8)
	tiles[witch_col][witch_row]=witch
	tiles[witch_col-1][witch_row]=witch
	tiles[witch_col-2][witch_row]=witch
	tiles[witch_col-1][witch_row-1]=witch
	tiles[witch_col-1][witch_row+1]=witch
	-- spawn some trees
	local num_trees=rnd_int(0,2)
	local i
	for i=1,num_trees do
		local col=rnd_int(2,14)
		local row=rnd_int(2,10)
		local tree=spawn_entity("tree",8*col-rnd_int(4,6),7*row-rnd_int(4,6))
		tiles[col][row]=tree
		tiles[col+1][row]=tree
		tiles[col][row+1]=tree
		tiles[col+1][row+1]=tree
	end
	-- spawn some fences
	local num_fences=rnd_int(1,3)
	for i=1,num_fences do
		generate_fence(tiles)
	end
	-- make a tombstone
	local num_tombstones=rnd_int(0,20)
	for i=1,num_tombstones do
		local col=2*rnd_int(1,7)
		local row=2*rnd_int(1,5)
		if not tiles[col][row] then
			tiles[col][row]=spawn_entity("tombstone",8*col-rnd_int(6,7),7*row-rnd_int(6,7))
		end
	end
	-- make some enemies
	local num_minions=rnd_int(0,3)
	for i=1,num_minions do
		local col=rnd_int(6,13)
		local row=rnd_int(2,10)
		if not tiles[col][row] then
			tiles[col][row]=spawn_entity(ternary(rnd()<0.5,"skeleton","frog"),8*col-rnd_int(6,7),7*row-rnd_int(6,7))
		end
	end
end

function generate_fence(tiles)
	local fence_col=rnd_int(3,12)
	local fence_row=rnd_int(5,11)
	local vx=ternary(rnd()<0.5,1,-1)
	local horizontality=rnd()
	local i=0
	while fence_col==mid(1,fence_col,16) and fence_row==mid(2,fence_row,11) and (i<4 or rnd()<0.9) do
		i+=1
		if rnd()<horizontality then
			fence_col+=vx
			if tiles[fence_col] and not tiles[fence_col][fence_row] then
				tiles[fence_col][fence_row]=spawn_entity("horizontal_fence",8*fence_col-8,7*fence_row-6)
			end
		else
			fence_row-=1
			if tiles[fence_col] and not tiles[fence_col][fence_row] then
				tiles[fence_col][fence_row]=spawn_entity("vertical_fence",8*fence_col-ternary(vx>0,1,9),7*fence_row-6)
			end
		end
	end
end

function update_game()
	-- update each entity
	foreach(entities,function(entity)
		if decrement_counter_prop(entity,"frames_to_death") then
			entity:die()
		else
			if not entity.is_hallucination then
				entity:update()
				increment_counter_prop(entity,"frames_alive")
				decrement_counter_prop(entity,"invincibility_frames")
				if entity.keep_in_bounds then
					if entity.x<0 then
						entity.x=0
					elseif entity.x+entity.width>121 then
						entity.x=121-entity.width
					end
					if entity.y<0 then
						entity.y=0
					elseif entity.y+entity.height>77 then
						entity.y=77-entity.height
					end
				end
			end
		end
	end)
	-- check for hits
	local i
	for i=1,#entities do
		local e1=entities[i]
		local j
		for j=1,#entities do
			local e2=entities[j]
			if i!=j and not e1.is_hallucination and not e2.is_hallucination and band(e1.hitbox_channel,e2.hurtbox_channel)>0 then
				if rects_overlapping(e1.x,e1.y,e1.width,e1.height,e2.x,e2.y,e2.width,e2.height) then
					e1:on_hit(e2)
					hurt_entity(e2,e1)
				end
			end
		end
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	filter_list(entities,function(entity)
		return entity.is_alive
	end)
	-- sort entities for drawing
	sort_list(entities,function(entity1,entity2)
		return entity1.y>entity2.y
	end)
end

function draw_game(shake_x)
	-- draw play grid
	local camera_x=shake_x-2
	local camera_y=-25
	camera(camera_x,camera_y)
	-- local c,r
	-- for c=0,15 do
	-- 	line(8*c,0,8*c,77)
	-- end
	-- for r=0,11 do
	-- 	line(0,7*r,120,7*r)
	-- end
	-- draw each entity
	if player_has_curse("vertigo") then
		camera(camera_x+7*cos(scene_frame/250),camera_y+7*sin(scene_frame/250))
		draw_game_objects()
		camera(camera_x-7*cos(scene_frame/250),camera_y-7*sin(scene_frame/250))
		draw_game_objects()
	else
		draw_game_objects()
	end
	if player_has_curse("near-sighted") then
		color(0)
		rectfill(-10,-10,player.x-31,87)
		rectfill(player.x+38,-10,137,87)
		rectfill(-10,-10,137,player.y-34)
		rectfill(-10,player.y+35,137,87)
	end
	-- draw ui
	camera(shake_x)
	color(0)
	rectfill(0,0,127,16)
	rectfill(0,111,127,127)
	-- draw player health
	if player_has_curse("monochrome") then
		pal(8,14)
		pal(14,15)
	end
	local heart_mult=ternary(player_has_curse("big-heart"),3,1)
	local i
	for i=1,3 do
		sspr(ternary(player.health<i,77,68),0,9,8,65+10*(i-2.5)*heart_mult,130-15*heart_mult,9*heart_mult,8*heart_mult)
	end
end

function draw_game_objects()
	rect(0,0,120,77,ternary(player_has_curse("monochrome"),2,1))
	-- draw each entity
	foreach(entities,function(entity)
		pal()
		entity:draw()
	end)
	pal()
end

-- curse scene methods
function init_curse()
	add(player_curses,curses[#player_curses+1])
end

function update_curse()
	if scene_frame>20 and btnp2("z") then
		init_scene("game")
	end
end

function draw_curse()
	color(13)
	print("with her dying breath,",20,8)
	print("the witch lays a curse on you!",4,15)
	if scene_frame%40<30 then
		print("press z to continue",26,108)
	end
	-- rect(54,43,74,63)
	-- color(0)
	-- rectfill(57,43,71,63)
	-- rectfill(54,46,74,60)
	local curse=player_curses[#player_curses]
	color(6)
	print(curse[2],64-2*#curse[2],44)
	local i
	for i=1,#curse[3] do
		print(curse[3][i],64-2*#curse[3][i],61+7*i)
	end
	-- rect(56,45,72,61,8)
end

-- death scene methods
function init_death()
end

function update_death()
	if scene_frame>30 and btnp2("z") then
		player_curses={}
		shuffle_list(curses)
		init_scene("game")
	end
end

function draw_death()
	color(7)
	print("i'm real sorry but",28,25)
	print("you died :(",42,35)
	if #player_curses>0 then
		print("good news tho:",36,60)
		print("you collected "..#player_curses.." curse"..ternary(#player_curses==1,"","s").."!",17,70)
	end
	color(13)
	if scene_frame%40<30 then
		print("press z to continue",26,108,13)
	end
end

-- entity functions
function spawn_entity(class_name,x,y,args,skip_init)
	local entity
	local super_class_name=entity_classes[class_name].extends
	if super_class_name then
		entity=spawn_entity(super_class_name,x,y,args,true)
	else
		-- create the basic entity
		entity={
			-- lifetime props
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			-- hit props
			health=1,
			damage=1,
			hitbox_channel=0,
			hurtbox_channel=0,
			invincibility_frames=0,
			-- collision props
			collision_channel=0,
			obstacle_channel=0,
			-- spatial props
			x=x or 0,
			y=y or 0,
			vx=0,
			vy=0,
			width=1,
			height=1,
			-- basic entity methods
			init=noop,
			update=function(self)
				self:apply_velocity()
			end,
			apply_velocity=function(self)
				local vx,vy=self.vx,self.vy
				-- entities that don't collide with anything are real simple
				if self.collision_channel<=0 then
					self.x+=vx
					self.y+=vy
				-- otherwise we have a lot of work to do
				elseif vx!=0 or vy!=0 then
					-- move in small steps
					local move_steps=ceil(max(abs(vx),abs(vy))/1.05)
					local t
					for t=1,move_steps do
						if vx==self.vx then
							self.x+=vx/move_steps
						end
						if vy==self.vy then
							self.y+=vy/move_steps
						end
						-- check for collisions against other entities
						local d
						for d=1,#direction_attrs do
							local dir=direction_attrs[d]
							local axis,vel,size,mult=dir[2],dir[3],dir[4],dir[5]
							local i
							for i=1,#entities do
								local entity=entities[i]
								if band(self.collision_channel,entity.obstacle_channel)>0 and self!=entity and mult*self[vel]>=mult*entity[vel] and not self.is_hallucination and not entity.is_hallucination then
									-- they can collide, now check to see if there is overlap
									local self_sub={}
									self_sub.x=self.x+1.1
									self_sub.y=self.y+1.1
									self_sub.width=self.width-2.2
									self_sub.height=self.height-2.2
									self_sub[axis],self_sub[size]=self[axis]+ternary(mult>0,self[size]/2,0),self[size]/2
									if rects_overlapping(
										self_sub.x,self_sub.y,self_sub.width,self_sub.height,
										entity.x,entity.y,entity.width,entity.height) then
										-- there was a collision
										self[axis],self[vel]=entity[axis]+ternary(mult<0,entity[size],-self[size]),entity[vel]
										self:on_collide(dir[1],entity)
									end
								end
							end
						end
					end
				end
			end,
			draw=function(self)
				self:draw_outline(8)
			end,
			draw_outline=function(self,color)
				rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color or 8)
			end,
			center_x=function(self)
				return self.x+self.width/2
			end,
			center_y=function(self)
				return self.y+self.height/2
			end,
			-- death methods
			die=function(self)
				self:on_death()
				self.is_alive=false
			end,
			despawn=function(self)
				self.is_alive=false
			end,
			on_death=noop,
			-- hit methods
			on_hit=noop,
			on_hurt=noop,
			-- collision methods
			on_collide=noop
		}
	end
	entity.class_name=class_name
	-- add class properties/methods onto it
	local k,v
	for k,v in pairs(entity_classes[class_name]) do
		entity[k]=v
	end
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init()
		-- add it to the list of entities-to-be-added
		add(new_entities,entity)
	end
	if player_has_curse("weakness") and class_name!="player" then
		entity.health+=1
	end
	-- return it
	return entity
end

function add_new_entities()
	foreach(new_entities,function(entity)
		add(entities,entity)
	end)
	new_entities={}
end

function hurt_entity(e2,e1) -- e2 is hurt by e1
	if e2.invincibility_frames<=0 then
		e2.health-=1--e1 and e1.damage or 1
		e2.invincibility_frames=5
		if e2:on_hurt(e1)!=false and e2.health<=0 then
			e2:die()
		end
	end
end

-- scene functions
function init_scene(s)
	freeze_frames,screen_shake_frames=0,0
	scene,scene_frame=scenes[s],0
	scene[1]()
end

-- helper methods
function freeze_and_shake_screen(freeze,shake)
	freeze_frames=max(freeze,freeze_frames)
	screen_shake_frames=max(shake,screen_shake_frames)
end

function player_has_curse(s)
	local i
	for i=1,#player_curses do
		if player_curses[i][1]==s then
			return true
		end
	end
end

function debug_add_curse(s)
	local i
	for i=1,#curses do
		if curses[i][1]==s then
			add(player_curses,curses[i])
		end
	end
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(rnd_float(min_val,max_val+1))
end

-- generates a random number between min_val and max_val
function rnd_float(min_val,max_val)
	return min_val+rnd(max_val-min_val)
end

function button_string_to_index(s)
	if s=="right" then
		return 1
	elseif s=="left" then
		return 0
	elseif s=="down" then
		return 3
	elseif s=="up" then
		return 2
	elseif s=="z" then
		return 4
	elseif s=="x" then
		return 5
	end
end

function btn2(n)
	return buttons[button_string_to_index(n)]
end

function btnp2(n)
	return button_presses[button_string_to_index(n)]
end

function sspr2(sx,sy,sw,sh,x,y,fh,fv,w,h)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,(w or sw),(h or sh),fh,fv)
end

-- round a number up to the nearest integer
function ceil(n)
	return -flr(-n)
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return n-12000
	end
	return n+1
end

-- increment_counter on a property of an object
function increment_counter_prop(obj,k)
	obj[k]=increment_counter(obj[k])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,k)
	if obj[k]>0 then
		obj[k]=decrement_counter(obj[k])
		return obj[k]<=0
	end
	return false
end

-- check for aabb overlap
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1+w1>x2 and x2+w2>x1 and y1+h1>y2 and y2+h2>y1
end

-- sorts list (inefficiently) based on func
function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- filters list to contain only entries where func is truthy
function filter_list(list,func)
	local num_deleted,i=0 -- ,nil
	for i=1,#list do
		if not func(list[i]) then
			list[i]=nil
			num_deleted+=1
		else
			list[i-num_deleted],list[i]=list[i],nil
		end
	end
end

-- shuffles a list randomly
function shuffle_list(list)
	local i
	for i=1,#list do
		local j=rnd_int(i,#list)
		list[i],list[j]=list[j],list[i]
	end
end

function index_of(list,val)
	local i
	for i=1,#list do
		if list[i]==val then
			return i
		end
	end
end

-- takes in a string direction and returns a x,y vector
function dir_to_vector(dir,mag)
	mag=mag or 1
	if dir=="left" then
		return -mag,0
	elseif dir=="right" then
		return mag,0
	elseif dir=="up" then
		return 0,-mag
	elseif dir=="down" then
		return 0,mag
	else
		return 0,0
	end
end

__gfx__
0666d002660000000000000000000000bbb000000005000500000050500000000000088808880055505550000000dd00000000dd000000000000000000000000
66666d662d6d000000000000bbb0000b1b1b00000505050505005050050050050050888888ee855005005500000dd00000000dd0000000000000000000000000
6ddd6d62d26d00000100000b1b1b0000bbbbb0000555555555005505055050050050888888ee85000000050000dddd000000dddd000000000000000000000000
66666d6d62dd010000001000bbbbb000b3bb3b000505050505005050050050050500888888ee8500000005000002200000000220020000000000000000000000
6dd66d6d266d001111110000bbb3b00b00b303300505050505005000505050050005088888880050000050000042440002dd42440d0000000000000000000000
66666dd6626d01000000010b03b33000000030030555555555005505550550050050008888800005000500000dd4dd00000dd4ddd00000000000000000000000
66666d6666dd0000000000000000000000000000050505050500505050505005005000088800000050500000d2dddd0000dddddd000000000000000000000000
0a00000000000000000000000000000003000000000000000000000000000000000000008000000005000044442dd4454444ddd4450000000000000000000000
0a0aaaa999aaaa0000000000000000000b3000000000000000000000000000000000000000000000000000055ddd4454055ddd44540000000000000000000000
0a0000000000000000000000000000000b30000000000000000000000000000000000000000000000000000055dd04450055dd04450000000000000000000000
0a0000000000000000000000000000000b30000000000000000000000000000000000000000000000000000000d000000000d000000000000000000000000000
090000000000000000000000000000000b300000000000000000000000a000a000a000a000a000a000a00a0000a00a0000a00a0000a000a000a000a000a000a0
090000000000000000000000000000000b3000000000000000000000009929900099299000992990009922900099229000992290009222900092229000922290
09000000000000000000000000000000033000000000000000000000002444200024442000244420002244200022442000224420002222200022222000222220
0a0000000000000000000000a000a000333300000000000000000000002444200024442000244420002244200022442000224420002222200022222000222220
0a000000000000000000000099299000a0300000a00a000000000000002a4a200a2a4a20002a4a24022aa4a0022aa4a0022aa4a000222220042222200022222a
0a000000000000000000000024442000922a000099229000000000000aa9a9a40aa9a94000aaa9a40aa99a9400aa9a900aa99a940422222a042222200022222a
0a0000000000000000000000244420022229000022442000000000000aa9a9940499a94000aaa9940aa99a9400a49a900aa99a94049222aa049222aa04922294
0000004004004400000000002a4a200222220002224420003000000004999994009999400049999004999994009449904099994404999994009999aa04999990
00400040400040000000000aa9a9a0022222a0222aa4a40033bbbbb3009a9a90009a9a90009a9a900099a9a00099a9a00099a9a0009999900099999404999990
00040004000404400000000aa4a940222229a0229aaa94433333333000aa9aa000aa9aa000aa9aa000aaa9a000aaa9a000aaa9a000aaaaa000aaaaa000aaaaa0
00404002400420040000000094949022222900229aa4400030000000009909900099099000990990009909900099099000990990009909900099099000990990
4000440040440000000000009caa9022229900009999900000000000009909900000099000990000009909900990099000999900009909900099000000000990
044404424442000400400000cccca0022999000099a9a00000000000000000000000000000000000000000000000000000000000000000000000000000000000
4022424224200444440000009c39900aaaaa0000aaa9a000000000000000000000022200000444000000000000022200000999000000000000022200000aaa00
0040244444204420040000009cb000099099000999099000000000000000000000222220009999900000000000222220009999a000000000002222200099a990
04002442424442000040000003b00000009900099009900000000000000000000a22222a0999a999000000000aaa22220449999a000000000aa222aa09999999
00000244444440000000000003b00000000000000000000000000000000000000aa222aa099aaaa9000000000aa9aa22022aa9aa000000000a999a9a099444a9
00000244444240000000000003b00000000000000000000000000000000000000a9444aa0aaaaaaa000000000a99aa440222aaaa00000000099aaa990aa222aa
00002242444242000000000003b00000000000000000000000000000000000000099a99000a222a00000000000a999900022222000000000009aa99000a222a0
0000244242444200000000000030000000000000000000000000000000000000000999000002220000000000000999000002220000000000000aa90000022200
00024244424442000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00442444444424000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000224422222400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000004200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
dd00dd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d100d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0dddd00dddd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08d8d0d8d8dd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
070700d7070100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07770000077700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70707000707070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07770000077700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07700000077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070070700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777770777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70776000007760700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00767700077670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700070070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
888e8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0080000000000000000000000000dd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
077000000000000000000000000dd000000000220000009a90000009900000000000000000000000000000000000000000000000000000000000000000000000
0aa70000000000000000000000dddd00000002442000099440000099990000000000000000000000000000000000000000000000000000000000000000000000
00aa7000000000000000000000022000000022442200099440000092290000000000000000000000a000000000a00000000a0000000000000000000000000000
0a0a700000000000000000000042440000000944900022aaa0000022220000000000000000000009a900000099a0000000999000000000000000000000000000
9000000000000000000000000dd4dd00000009999000aa9a9a000a2222a000000000000000000024942000022490000002222200000000000000000000000000
000000000000000000000000d2dddd00000009999000999999000992290000000000000000000024442000022440000002222200000000000000000000000000
000000000000000000000044442dd44500000999900099999900099229000000000000000000002a4a200022aa4a000002222200000000000000000000000000
0000000000000000000000055ddd4454000099999900099990000099990000000000000000000aa9a9aa00aa99a9a000a22222a0000000000000000000000000
00000000000000000000000055dd0445000099009900099990000099990000000000000000000999a999009999a9900099222900000000000000000000000000
00000000000000000000000000d00000000000009900099990000099990000000000000000000999999900999999900099222900000009000000000900000000
0000000000000000000000000000000000000000000000000000000000000000000000000000009a9a9000099a9a000009999900009099909009099900000000
000000000000000000000000000000000000000000000000000000000000000000000000000000aa9aa0000aaa9a00000aaaaa00000949490000994900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000099099000099099000009909900000944490000994400000000
00000000000000000000000000000000000000000000000000000000000000000000000000000099099000099099000009909900000094900000099400000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000999990000999990000000
0000000000000000000000000000000000000000000000000000000000000000dd00000000000000000000000000000000000000000999990000999990000000
000000000000000000000000000000000000000000000000000000000000000dddd0000000000000000000000000000000000000000999990000999990000000
00000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000999990000999990000000
00000000000000000000000000000000000000000000000000000000000000042440000000000000000000000000000000000000000999990000999990000000
00000000000000000000000000000000000000000000000000000000000000dd4dd0000000000000000000000000000000000000000990990000990990000000
0000000000000000000000000000000000000000000000000000000000000d2dddd0000000000000000000000000000000000000000990990000990990000000
0000000000000000000000000000000000000000000000000000000000044442dd445000000000aaa0000009aa90000009990000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055ddd44540000000094a490000994a20000099999000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000055dd044500000000944490000994420000092229000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000d00000000000002a4a200022aa4a0000022222000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000aa9a9aa00aa99a9a000a22222a00000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000999a999009999a99000992229000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000009999999009999999000992229000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000009a9a9000099a9a0000099999000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000aa9aa0000aaa9a00000aaaaa000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000990990000990990000099099000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000990990000990990000099099000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000022200000022200000002220000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000244420000224420000022222000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000244420000224420000022222000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000002a4a200022aa4a0000022222000000000000000000000000000
0000000000000000000000000000000000000000000222000000222000000022200000000000aa9a9a400aa99a94000422222a00000000000000000000000000
0000000000000000000000000000000000000000002444200002244200000222220000000000499a994004999a94000492229400000000000000000000000000
00000000000000000000000000000000000000000024442000022442000002222200000000004999994004999994000492229400000000000000000000000000
0000000000000000000000000000000000000000002d4d200022dd4d0000022222000000000009a9a9000099a9a0000099999000000000000000000000000000
00000000000000000000000000000000000000000ddddcc400dddddc4000422222d0000000000aa9aa0000aaa9a00000aaaaa000000000000000000000000000
00000000000000000000000000000000000000000dddccc400ddddcc40004c222dd0000000000990990000990990000099099000000000000000000000000000
00000000000000000000000000000000000000000dddccc400ddddcc40004c22ddd0000000000990990000990990000099099000000000000000000000000000
00000000000000000000000000000000000000000ddcccc000dddccc00000ccccdd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000dd2022000ddd0220000022022d0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000022022000022022000002202200000000000000000000000000000000000000000000009900000000000000
00000000000000000000000000000000000000000022022000022022000002202200000000000000000000000000000000000000000000094440000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000022200000022200000002220000000000099490000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000244420000224420000022222000000000999999000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000244420000224420000022222000000000999999000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000002d4d200022dd4d0000022222000000000999499000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000ddcdcc400ddccdc4000422222d00000000099490000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000004ccccc4004cccdc40004c222c400000000044990000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000004ccccc4004ccccc40004c22cc400000000099999000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000ccccc0000ccccc00000ccccc000000000099099000000000000
00000000000000000000000000000000000022000000022000000002200000000000000000000dd0dd0000dd0dd00000dd0dd000000000099099000000000000
00000000000000000000000000000000000244200000224200000022220000000000000000000dd0dd0000dd0dd00000dd0dd000000000000000000000000000
00000000000000000000000000000000000244200000224200000022220000000000000000000dd0dd0000dd0dd00000dd0dd000000000000000000000000000
00000000000000000000000000000000000288200002228800000022220000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000888dd40008888d40000422228000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000888dd4000888dd400004d2288000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000888dd4000888dd400004d2888000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000088ddd0000888dd000000ddd88000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000008822200000882200000022228000000000000000000000000000000000000000000000000000000000000000000123
00000000000000000000000000000000000222200000222200000022220000000000000000000000000000000000000000000000000000000000000000004567
000000000000000000000000000000000002222000002222000000222200000000000000000000000000000000000000000000000000000000000000000089ab
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cdef

__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

