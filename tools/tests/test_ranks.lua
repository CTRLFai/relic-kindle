-- Rank ladder. Run from relic.koplugin/:  luajit ../tools/tests/test_ranks.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local now = os.time()
assert(#Game.RANKS == 12 and Game.RANKS[12].level == 40)
for i = 2, #Game.RANKS do assert(Game.RANKS[i].level > Game.RANKS[i - 1].level) end
-- respaced 2026-10-22: level 10 (Mike at day 17) is Ensign, working toward Lieutenant JG
assert(Game.rankIndex(1) == 1 and Game.rankIndex(6) == 1 and Game.rankIndex(7) == 2 and Game.rankIndex(10) == 2)
assert(Game.rankIndex(12) == 3 and Game.rankIndex(39) == 11 and Game.rankIndex(40) == 12 and Game.rankIndex(99) == 12)
-- new player: no promotion pending
local s = Game.newState(now)
assert(not Game.pendingPromotion(s))
s.level = 7; assert(Game.pendingPromotion(s) == 2)
s.level = 16; assert(Game.pendingPromotion(s) == 4) -- several at once: highest
-- migration from v10: exactly one promotion shown (the current rank)
local old = Game.newState(now); old.save_version = 10; old.rank_seen = nil; old.level = 10
local m = Game.migrate(old)
-- v11 would show one promotion, but v13 settles on the respaced rank quietly
assert(m.save_version >= 13 and m.rank_seen == 2 and not Game.pendingPromotion(m))
-- Mike's save: v12, Lieutenant already shown at level 10 -> Ensign, no screen; next promotion at 12
local mk = Game.newState(now); mk.save_version = 12; mk.rank_seen = 4; mk.level = 10
Game.migrate(mk)
assert(mk.rank_seen == 2 and not Game.pendingPromotion(mk))
mk.level = 12; assert(Game.pendingPromotion(mk) == 3)
-- the next rank is about a third of the way off at Mike's level 10 + 773 XP
local info = Game.rankInfo({ level = 10, xp = 773 })
assert(info.rank.name == "Ensign" and info.next.name == "Lieutenant JG" and info.pct_next > 0.4 and info.pct_next < 0.8, info.pct_next)
local low = Game.newState(now); low.save_version = 10; low.rank_seen = nil; low.level = 2
assert(Game.migrate(low).rank_seen == 1 and not Game.pendingPromotion(low))
-- progress numbers stay in range
for _, lv in ipairs{ 1, 9, 10, 12, 39, 40, 55 } do
  local t = Game.newState(now); t.level = lv; t.xp = 5
  local i = Game.rankInfo(t)
  assert(i.pct_next >= 0 and i.pct_next <= 1 and i.pct_top >= 0 and i.pct_top <= 1)
  if lv >= 40 then assert(not i.next and i.pct_top == 1) end
end
print("test_ranks OK")
