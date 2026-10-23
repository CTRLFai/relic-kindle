-- Logic tests for steps sync and the phone inbox. Run from relic.koplugin/:  luajit ../tools/tests/test_steps.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
package.preload["datastorage"]=function() return {getSettingsDir=function() return "/tmp" end} end
package.preload["ui/network/manager"]=function() return {isConnected=function() return true end} end
package.preload["logger"]=function() return {warn=function() end} end
local Game = dofile("game.lua")
local src=io.open("inbox.lua"):read("*a")
local Inbox = load(src)()
local P=Inbox.parseSteps
local d=P("2026-10-08 5,234\n2026-10-09\n2026-10-10 400\n2026-10-11: 1 234\n2026-10-12=9.876")
assert(d["2026-10-08"]==5234 and d["2026-10-09"]==nil and d["2026-10-10"]==400 and d["2026-10-11"]==1234 and d["2026-10-12"]==9876)
local d2=P("2026-09-28 5234;\n2026-09-27 8012;"); assert(d2["2026-09-28"]==5234 and d2["2026-09-27"]==8012)
local d3=P("2026-09-28 5234;2026-09-27 8,012;"); assert(d3["2026-09-28"]==5234 and d3["2026-09-27"]==8012)
local created=os.time{year=2026,month=9,day=28,hour=9}
local s=Game.newState(created); local now=os.time{year=2026,month=10,day=30,hour=15}
local big={}; for i=0,20 do big[os.date("%Y-%m-%d", now-i*86400)]=8000 end
local g1=Game.syncSteps(s,big,now); local g2=Game.syncSteps(s,big,now)
print("21-day payload", g1, g2); assert(g2==0)
-- carry
local s2=Game.newState(created); local n2=os.time{year=2026,month=10,day=9,hour=15}
assert(Game.syncSteps(s2,{["2026-10-08"]=7700},n2)==7); assert(Game.syncSteps(s2,{["2026-10-09"]=7700},n2)==8)
-- future
local g,f=Game.syncSteps(s2,{["2026-10-20"]=5000},n2); assert(g==0 and f==1)
-- pre-unlock
local pre=os.date("%Y-%m-%d", created + (Game.UNLOCK_DAY.map - 1) * 86400)  -- the day before the map opens
local g3=Game.syncSteps(Game.newState(created),{[pre]=9000},n2); assert(g3==0)
-- migrate
local o=Game.newState(created); o.save_version=4; o.steps_synced=nil; o.step_carry=nil
local m=Game.migrate(o); assert(m.save_version==Game.SAVE_VERSION and m.steps_synced and m.step_carry==0)
-- pull flow with fake request
local calls={}
local store={d={},readSetting=function(self,k) return self.d[k] end,saveSetting=function(self,k,v) self.d[k]=v end,flush=function() end,delSetting=function(self,k) self.d[k]=nil end}
store.d.todoist_project_id="P"
local tasks={{id="1",content="Relic Steps",description="2026-10-08 5,234"},{id="2",content="Buy milk",description=""},{id="3",content="Relic save 1",description="x"}}
local fakeReq=function(cfg,method,path,body) table.insert(calls,method.." "..path); if method=="GET" then return {results=tasks} end return true end
-- patch upvalue: inject via debug
local function setup(fn) for i=1,50 do local n=debug.getupvalue(fn,i); if not n then break end; if n=="request" then debug.setupvalue(fn,i,fakeReq) end; if n=="list" then local lf=debug.getupvalue(fn,i) end end end
local pull=Inbox.pull
for i=1,50 do local n,v=debug.getupvalue(pull,i); if not n then break end
  if n=="request" then debug.setupvalue(pull,i,fakeReq) end
  if n=="list" then for j=1,50 do local n2=debug.getupvalue(v,j); if not n2 then break end; if n2=="request" then debug.setupvalue(v,j,fakeReq) end end end
end
Inbox.config=function() return {todoist_token="x",todoist_base="b",todoist_project="Relic"} end
-- Inbox.pull calls Inbox.config? check
local added={} ; local got
local n=Inbox.pull(store,function(q) table.insert(added,q.title) end,true,function(days) got=days; return true end)
print(n, table.concat(added,","), table.concat(calls," | "))
assert(n==1 and added[1]=="Buy milk" and got["2026-10-08"]==5234)
-- second pull: close failed scenario -> task 2 still there, must not import again
calls={}; added={}
tasks={{id="2",content="Buy milk",description=""}}
n=Inbox.pull(store,function(q) table.insert(added,q.title) end,true,function() return true end)
print(n, #added, table.concat(calls," | ")); assert(n==0 and #added==0)
-- future: steps returns false -> no delete
calls={}; tasks={{id="9",content="relic steps",description="2030-01-01 5"}}
Inbox.pull(store,function() end,true,function() return false end)
for _,c in ipairs(calls) do assert(not c:match("DELETE")) end
print("ok")

-- v39 recurring Todoist tasks: understood -> repeating quest + DELETE; failed delete retried, not re-imported;
-- not understood -> one-off quest, task left alone; pre-v39 recurring (seen, closed before) -> imported once
Inbox.parseRecurrence = Game.parseRecurrence
local store2={d={todoist_project_id="P"},readSetting=store.readSetting,saveSetting=store.saveSetting,flush=function() end,delSetting=store.delSetting}
local got_rep
local function addq(q) table.insert(added,q.title); got_rep=q.rep end
calls={}; added={}
tasks={{id="20",content="Morning walk",description="",due={date="2026-10-22",is_recurring=true,string="every day"}}}
n=Inbox.pull(store2,addq,true)
assert(n==1 and got_rep and got_rep.kind=="daily" and calls[#calls]=="DELETE tasks/20", table.concat(calls," | "))
calls={}; added={}
n=Inbox.pull(store2,addq,true)   -- delete failed, task still listed
assert(n==0 and #added==0 and calls[#calls]=="DELETE tasks/20")
calls={}; added={}; got_rep=nil
tasks={{id="21",content="Odd one",description="",due={date="2026-10-22",is_recurring=true,string="every 3rd workday after holidays"}}}
tasks[1].due.string="every fortnightish"
n=Inbox.pull(store2,addq,true)
assert(n==1 and got_rep==nil); for _,c in ipairs(calls) do assert(not c:match("21"), c) end
calls={}; added={}
n=Inbox.pull(store2,addq,true)
assert(n==0 and #added==0); for _,c in ipairs(calls) do assert(not c:match("21"), c) end
-- pre-v39: id already in imported_ids (closed back then), understood -> imported once as repeating, then deleted
store2.d.imported_ids={"30"}
calls={}; added={}; got_rep=nil
tasks={{id="30",content="Gym",description="",due={date="2026-10-26",is_recurring=true,string="every mon"}}}
n=Inbox.pull(store2,addq,true)
assert(n==1 and got_rep and got_rep.days[2] and calls[#calls]=="DELETE tasks/30")
calls={}; added={}
n=Inbox.pull(store2,addq,true); assert(n==0 and #added==0)
local r, known = Game.parseRecurrence("every 400 days"); assert(r.n==365 and known)
r, known = Game.parseRecurrence("every weekend"); assert(r.days[1] and r.days[7] and known)
r, known = Game.parseRecurrence("every other monday"); assert(r.n==14)
r, known = Game.parseRecurrence("every mondays"); assert(r.days[2])
r, known = Game.parseRecurrence("every blue moon"); assert(not known)
assert(select(2, Game.parseRecurrence("every day")))
print("recurring inbox ok")
