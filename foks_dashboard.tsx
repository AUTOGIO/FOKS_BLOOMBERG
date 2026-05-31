import { useState, useEffect, useRef } from "react";

const F = "'Courier New', Courier, monospace";
const AMBER="#f59e0b", GREEN="#a3e635", CYAN="#22d3ee", RED="#ff3333";
const DIM="#444", MID="#888", BG0="#000", BG1="#050505", BG2="#0a0a0a", BG3="#0f0f0f";
const BORDER="#1a1a1a", BORDER2="#222";

const THEMES = {
  amber:{name:"AMBER",primary:AMBER,top:"#1a1200",topAccent:AMBER,topText:"#f59e0b",
    bg0:"#000",bg1:"#050505",bg2:"#0a0a0a",border:"#1a1a1a",border2:"#222",
    tickerBg:"#080800",tickerBorder:"#1a1a00"},
  blue:{name:"BLUE",primary:"#1e90ff",top:"#000d1f",topAccent:"#1e90ff",topText:"#7ec8ff",
    bg0:"#00050f",bg1:"#000d1a",bg2:"#001122",border:"#002244",border2:"#003366",
    tickerBg:"#000a18",tickerBorder:"#001a33"},
};

const AGENTS = [
  {id:"dc",    short:"DC",       status:"CONNECTED",latency:"4ms",   color:GREEN},
  {id:"cursor",short:"CURSOR",   status:"IDLE",     latency:"—",     color:AMBER},
  {id:"claw",  short:"OPENCLAW", status:"OFFLINE",  latency:"—",     color:RED},
  {id:"claude",short:"CLAUDE",   status:"ACTIVE",   latency:"—",     color:CYAN},
  {id:"ifttt", short:"IFTTT",    status:"CONNECTED",latency:"88ms",  color:GREEN},
  {id:"ha",    short:"HA",       status:"ERROR",    latency:"—",     color:RED},
];

const STATUSES = ["Backlog","In Progress","Done","Blocked"];
const SS = {
  "Backlog":    {bg:"#0a0a0a",border:"#333",   text:"#888",tag:"QUEUE"},
  "In Progress":{bg:"#0a0f00",border:"#4a7c00",text:GREEN, tag:"ACTV"},
  "Done":       {bg:"#000d0a",border:"#00594a",text:CYAN,  tag:"CLOS"},
  "Blocked":    {bg:"#110000",border:"#8b0000",text:RED,   tag:"HALT"},
};

let uid = 500;

const INIT_PROJECTS = [
  {id:"ffa",short:"FFA",name:"FULOFILO ANALYTICS PRO",sector:"DATA/ML",color:AMBER,
   path:"/Users/eduardofgiovannini/Documents/GitHub/fulofilo-analytics",
   status:"ACTIVE",pct:42,phaseIdx:1,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:null,
   tasks:[{id:1,text:"Relocate project to ~/dev/fulofilo-analytics",phase:"P1",status:"Done"},
          {id:2,text:"Initialize git repo + .gitignore",phase:"P1",status:"Done"},
          {id:3,text:"Nine-sheet Excel master workbook (openpyxl)",phase:"P2",status:"In Progress"},
          {id:4,text:"Product categorization system BR retail",phase:"P2",status:"In Progress"},
          {id:5,text:"Polars + DuckDB pipeline core",phase:"P3",status:"Backlog"},
          {id:6,text:"Streamlit UI improvements",phase:"P3",status:"Backlog"},
          {id:7,text:"pytest pipeline hardening",phase:"P4",status:"Backlog"},
          {id:8,text:"M3/macOS optimizations",phase:"P5",status:"Backlog"}]},
  {id:"fts",short:"FTS",name:"FOKS TRINITY STACK",sector:"INFRA",color:"#a855f7",
   path:"/Users/eduardofgiovannini/dev/foks",
   status:"ACTIVE",pct:71,phaseIdx:4,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:null,
   tasks:[{id:9,text:"Desktop Commander v0.2.38 installed",phase:"CORE",status:"Done"},
          {id:10,text:".cursorrules configured under ~/dev",phase:"CORE",status:"Done"},
          {id:11,text:"Workspace Launcher LaunchAgent + deploy",phase:"TRIG",status:"Done"},
          {id:12,text:"Preflight validation + Shortcuts/Siri",phase:"TRIG",status:"Done"},
          {id:13,text:"Skill file integration for Claude context",phase:"INTL",status:"In Progress"},
          {id:14,text:"Session aliases ff-launch ff-sync ff-report",phase:"INTL",status:"In Progress"},
          {id:15,text:"CPU/memory daemon psutil + JSONL",phase:"MON",status:"Done"}]},
  {id:"lod",short:"LOD",name:"LIFE OS DJANGO",sector:"PRODUCT",color:CYAN,
   path:"/Users/eduardofgiovannini/Documents/GitHub/PersonalLifeOS",
   status:"ACTIVE",pct:12,phaseIdx:0,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:"Django scaffold not started",
   tasks:[{id:16,text:"Django project scaffold + DB schema",phase:"CORE",status:"Backlog"},
          {id:17,text:"Pomodoro timer module",phase:"UI",status:"Backlog"},
          {id:18,text:"Gamification + mood tracking",phase:"UI",status:"Backlog"},
          {id:19,text:"Telegram/WhatsApp reminder integration",phase:"TRIG",status:"Backlog"},
          {id:20,text:"Kitesurfing wind alerts weather API",phase:"INTL",status:"Backlog"},
          {id:21,text:"AI nudges module",phase:"INTL",status:"Blocked"}]},
  {id:"gmc",short:"GMC",name:"GMC / AUTOGIO",sector:"FINANCE",color:"#f97316",
   path:"/Users/eduardofgiovannini/AUTOGIO",
   status:"ACTIVE",pct:28,phaseIdx:0,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:"SwiftOrganizerX scope undefined",
   tasks:[{id:22,text:"SEFAZ-PB fiscal automation baseline",phase:"CORE",status:"In Progress"},
          {id:23,text:"giovannini-finance portfolio schema",phase:"CORE",status:"Backlog"},
          {id:24,text:"SwiftOrganizerX scope definition",phase:"CORE",status:"Blocked"},
          {id:25,text:"Macro regime-aware allocation rules",phase:"INTL",status:"Backlog"},
          {id:26,text:"Risk-first capital preservation model",phase:"INTL",status:"Backlog"}]},
  {id:"has",short:"HAS",name:"HOME ASSISTANT",sector:"OPS",color:RED,
   path:"/Users/eduardofgiovannini/.homeassistant",
   status:"HALT",pct:60,phaseIdx:3,phases:["INSTALL","CONFIG","INTEGRATE","FIX","STABLE"],blocker:"Tuya 0-device auth failure",
   tasks:[{id:27,text:"Re-authenticate Tuya via Smart Life account",phase:"FIX",status:"In Progress"},
          {id:28,text:"Restore 12 HomeKit entities to available",phase:"FIX",status:"Blocked"},
          {id:29,text:"Verify Tuya registry before any restore",phase:"FIX",status:"Backlog"}]},
  {id:"gfin",short:"GFN",name:"GIOVANNINI FINANCE",sector:"FINANCE",color:"#f97316",
   path:"/Users/eduardofgiovannini/AUTOGIO/giovannini-finance",
   status:"PAUSED",pct:35,phaseIdx:1,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:null,
   tasks:[{id:30,text:"NF-e receipt parser Python",phase:"CORE",status:"Done"},
          {id:31,text:"BCB macro data integration",phase:"CORE",status:"Done"},
          {id:32,text:"React/Vite offline frontend",phase:"UI",status:"In Progress"},
          {id:33,text:"HTML + XLSX report output",phase:"UI",status:"Backlog"},
          {id:34,text:"Portfolio schema design",phase:"CORE",status:"Backlog"}]},
  {id:"swx",short:"SWX",name:"SWIFTORGANIZERX",sector:"NATIVE",color:"#38bdf8",
   path:"/Users/eduardofgiovannini/AUTOGIO/SwiftOrganizerX",
   status:"PAUSED",pct:20,phaseIdx:0,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:"Scope collision with NEXUS/FoKS",
   tasks:[{id:35,text:"SwiftUI macOS file organizer scaffold",phase:"CORE",status:"Done"},
          {id:36,text:"Pareto storage analysis module",phase:"CORE",status:"In Progress"},
          {id:37,text:"Apple Notes + OpenAI integration",phase:"INTL",status:"Backlog"},
          {id:38,text:"Scope definition vs FoKS",phase:"CORE",status:"Blocked"}]},
  {id:"wsl",short:"WSL",name:"FOKS WORKSPACE LAUNCHER",sector:"INFRA",color:GREEN,
   path:"/Users/eduardofgiovannini/foks/workspace_launch.sh",
   status:"COMPLETE",pct:100,phaseIdx:4,phases:["CORE","INTERFACE","TRIGGER","INTELLIGENCE","MONITORING"],blocker:null,
   tasks:[{id:39,text:"deploy.sh + workspace_launch.sh",phase:"CORE",status:"Done"},
          {id:40,text:"yabai_layout.sh 4-zone dual display",phase:"TRIG",status:"Done"},
          {id:41,text:"preflight_validate.sh",phase:"TRIG",status:"Done"},
          {id:42,text:"LaunchAgent plist + Siri trigger",phase:"TRIG",status:"Done"},
          {id:43,text:"21 PASS / 17 WARN / 0 FAIL validated",phase:"MON",status:"Done"}]},
];

const PROCESSES = [
  {pid:"1042",name:"foks-monitor daemon",   script:"foks-monitor/main.py",     status:"RUNNING",cpu:"0.3%",mem:"18MB", uptime:"6d 14h",type:"DAEMON",
   logs:["[6d14h] daemon init ok","[0d01h] threshold not breached","[0d00h] heartbeat ok"]},
  {pid:"2187",name:"SEFAZ fiscal watcher",  script:"autogio/sefaz_watch.py",   status:"RUNNING",cpu:"0.1%",mem:"11MB", uptime:"2d 03h",type:"WATCHER",
   logs:["[2d03h] watcher started","[0d05h] nf-e parsed ok x3","[0d00h] idle"]},
  {pid:"3304",name:"LM Studio inference",   script:"LM Studio.app",            status:"RUNNING",cpu:"4.2%",mem:"3.1GB",uptime:"0d 07h",type:"SERVICE",
   logs:["[0d07h] server started port 1234","[0d06h] model loaded: llama3-8b","[0d00h] idle"]},
  {pid:"4451",name:"Ollama local models",   script:"ollama serve",             status:"RUNNING",cpu:"1.1%",mem:"890MB",uptime:"0d 07h",type:"SERVICE",
   logs:["[0d07h] ollama serve started","[0d00h] ready"]},
  {pid:"5512",name:"FuloFilo Streamlit UI", script:"fulofilo-analytics/app.py",status:"IDLE",   cpu:"0.0%",mem:"42MB", uptime:"0d 02h",type:"UI",
   logs:["[0d02h] streamlit started port 8501","[0d00h] idle"]},
  {pid:"6630",name:"HA Core supervisor",    script:"homeassistant/core.py",    status:"ERROR",  cpu:"0.0%",mem:"210MB",uptime:"12d 0h",type:"SERVICE",
   logs:["[0d04h] tuya integration error: 0 devices","[0d00h] homekit: 12 entities offline","[0d00h] ERROR: connection refused"]},
  {pid:"7701",name:"psutil JSONL logger",   script:"foks-monitor/logger.py",   status:"RUNNING",cpu:"0.0%",mem:"8MB",  uptime:"6d 14h",type:"DAEMON",
   logs:["[6d14h] logger init","[0d00h] heartbeat ok"]},
  {pid:"8820",name:"GMC portfolio snapshot",script:"autogio/gmc_snapshot.sh",  status:"IDLE",   cpu:"0.0%",mem:"5MB",  uptime:"1d 00h",type:"SCRIPT",
   logs:["[1d00h] snapshot run ok","[0d00h] idle"]},
  {pid:"9901",name:"Yabai tiling engine",   script:"yabai --service",          status:"RUNNING",cpu:"0.2%",mem:"22MB", uptime:"0d 07h",type:"WM",
   logs:["[0d07h] yabai v7.1.17 started","[0d07h] 4-zone layout applied","[0d00h] running"]},
];

const AUTOMATIONS = [
  {id:"A01",name:"FoKS Workspace Launcher",  trigger:"LOGIN / SIRI",     type:"LAUNCHAGENT",lastRun:"TODAY 08:12",  status:"ACTIVE", agent:"DC"},
  {id:"A02",name:"CPU Threshold Alert",      trigger:"SUSTAINED 80%",    type:"DAEMON",     lastRun:"2d AGO 14:33", status:"ACTIVE", agent:"DC"},
  {id:"A03",name:"FuloFilo Master Sync",     trigger:"MANUAL / ff-sync", type:"ALIAS",      lastRun:"TODAY 11:05",  status:"ACTIVE", agent:"DC"},
  {id:"A04",name:"GMC LaunchAgent",          trigger:"LOGIN",            type:"LAUNCHAGENT",lastRun:"TODAY 08:13",  status:"ACTIVE", agent:"DC"},
  {id:"A05",name:"Yabai Layout Init",        trigger:"LOGIN",            type:"LAUNCHAGENT",lastRun:"TODAY 08:12",  status:"ACTIVE", agent:"DC"},
  {id:"A06",name:"Desk Sanity Check",        trigger:"MANUAL",           type:"SCRIPT",     lastRun:"3d AGO 09:00", status:"IDLE",   agent:"DC"},
  {id:"A07",name:"Mac Inventory Audit",      trigger:"MANUAL",           type:"SCRIPT",     lastRun:"7d AGO 10:30", status:"IDLE",   agent:"DC"},
  {id:"A08",name:"FuloFilo Backup",          trigger:"MANUAL / ff-backup",type:"ALIAS",     lastRun:"5d AGO 17:20", status:"IDLE",   agent:"DC"},
  {id:"A09",name:"Tuya Re-Auth Sequence",    trigger:"MANUAL",           type:"HA SCRIPT",  lastRun:"NEVER",        status:"PENDING",agent:"HA"},
  {id:"A10",name:"SEFAZ NF-e Parser",        trigger:"FILE WATCH",       type:"WATCHER",    lastRun:"TODAY 09:41",  status:"ACTIVE", agent:"DC"},
  {id:"A11",name:"Preflight Validate",       trigger:"PRE-LAUNCH",       type:"SCRIPT",     lastRun:"TODAY 08:11",  status:"ACTIVE", agent:"DC"},
  {id:"A12",name:"Git Branch Guard",         trigger:"GIT HOOK",         type:"HOOK",       lastRun:"TODAY 10:22",  status:"ACTIVE", agent:"CURSOR"},
];

const INIT_ALERTS = [
  {id:1,lvl:"HALT",msg:"HAS — Tuya Sharing API returns 0 devices. Re-auth via Smart Life required.",dismissed:false},
  {id:2,lvl:"WARN",msg:"GMC — SwiftOrganizerX scope undefined. Risk: collision with FoKS/NEXUS.",dismissed:false},
  {id:3,lvl:"WARN",msg:"LOD — Django scaffold not initiated. Phase CORE blocked.",dismissed:false},
  {id:4,lvl:"INFO",msg:"FFA — Phase P2 in progress. openpyxl master workbook 60% complete.",dismissed:false},
  {id:5,lvl:"INFO",msg:"FTS — Skill file integration pending. Claude context incomplete.",dismissed:false},
];

const INIT_LOG = [
  {t:"08:11:04",src:"PREFLIGHT",   msg:"21 PASS / 17 WARN / 0 FAIL",        lvl:"ok"},
  {t:"08:12:01",src:"LAUNCHAGENT", msg:"WORKSPACE LAUNCHER FIRED",           lvl:"ok"},
  {t:"08:12:03",src:"YABAI",       msg:"4-ZONE LAYOUT APPLIED DISPLAY 2",    lvl:"ok"},
  {t:"08:13:00",src:"DAEMON",      msg:"FOKS-MONITOR STARTED PID 1042",      lvl:"ok"},
  {t:"09:41:22",src:"WATCHER",     msg:"SEFAZ NF-e PARSE TRIGGERED",         lvl:"ok"},
  {t:"10:22:05",src:"GIT HOOK",    msg:"BRANCH GUARD: desk/imac-wip OK",     lvl:"ok"},
  {t:"11:05:33",src:"FF-SYNC",     msg:"FULOFILO MASTER SYNC COMPLETE",      lvl:"ok"},
  {t:"11:47:00",src:"ALERT",       msg:"HA: TUYA SHARING API 0 DEVICES",     lvl:"err"},
];

const GMC_DATA = {
  regime:{label:"RISK-OFF",color:RED,sub:"CAPITAL PRESERVATION MODE"},score:72,
  rates:[
    {pair:"USD/BRL",val:"5.14",  delta:"+0.023",up:false},
    {pair:"EUR/BRL",val:"5.61",  delta:"+0.011",up:false},
    {pair:"BTC/USD",val:"67,420",delta:"-1,240", up:false},
    {pair:"EUR/USD",val:"1.091", delta:"+0.002", up:true},
    {pair:"XAU/USD",val:"2,331", delta:"+8.40",  up:true},
    {pair:"CDI/YR", val:"10.65%",delta:"—",      up:null},
  ],
  allocation:[
    {label:"CASH/FIXED",  pct:45,color:GREEN},
    {label:"EQUITIES",    pct:20,color:AMBER},
    {label:"REAL ESTATE", pct:20,color:CYAN},
    {label:"CRYPTO",      pct:8, color:"#a855f7"},
    {label:"INTL/OTHER",  pct:7, color:"#38bdf8"},
  ],
  signals:[
    {label:"SELIC RATE",val:"10.50%",status:"NEUTRAL"},
    {label:"IPCA YOY",  val:"3.93%", status:"OK"},
    {label:"USD TREND",  val:"STRONG",status:"WARN"},
    {label:"EQUITIES",   val:"CAUTION",status:"WARN"},
  ],
};

const LIFEOS_MODULES = [
  {id:"pomo",  label:"POMODORO",     icon:"⏱",path:"localhost:8000/pomodoro",  status:"IDLE",   key:"⌘1"},
  {id:"wind",  label:"WIND ALERT",   icon:"🪁",path:"localhost:8000/wind",     status:"ACTIVE", key:"⌘2"},
  {id:"mood",  label:"MOOD LOG",     icon:"🧠",path:"localhost:8000/mood",     status:"IDLE",   key:"⌘3"},
  {id:"nudge", label:"AI NUDGES",    icon:"🤖",path:"localhost:8000/nudges",   status:"RUNNING",key:"⌘4"},
  {id:"gamif", label:"GAMIFICATION", icon:"🏆",path:"localhost:8000/game",     status:"IDLE",   key:"⌘5"},
  {id:"remind",label:"REMINDERS",    icon:"📲",path:"localhost:8000/reminders",status:"ACTIVE", key:"⌘6"},
];

const QUICK_ACTIONS = ["LAUNCH WORKSPACE","SYNC GIT","RUN AUDIT","EXPORT OBSIDIAN","HA REAUTH","FF LAUNCH","DESK CHECK","KILL ALL IDLE"];

/* ── HELPERS ── */
function pad(n){return String(n).padStart(2,"0");}
function statusColor(s){
  if(s==="RUNNING"||s==="ACTIVE"||s==="COMPLETE"||s==="CONNECTED"||s==="OK")return GREEN;
  if(s==="ERROR"||s==="HALT"||s==="OFFLINE")return RED;
  if(s==="IDLE"||s==="PAUSED")return MID;
  if(s==="PENDING"||s==="NEUTRAL"||s==="WARN")return AMBER;
  return MID;
}
function Clock(){
  var [t,setT]=useState(new Date());
  useEffect(function(){var iv=setInterval(function(){setT(new Date());},1000);return function(){clearInterval(iv);};},[]);
  return <span style={{color:AMBER,fontFamily:F,letterSpacing:2}}>{pad(t.getHours())}:{pad(t.getMinutes())}:{pad(t.getSeconds())} BRT</span>;
}
function Blink({color}){
  var [on,setOn]=useState(true);
  useEffect(function(){var iv=setInterval(function(){setOn(function(v){return !v;});},700);return function(){clearInterval(iv);};},[]);
  return <span style={{color:color||GREEN,opacity:on?1:0}}>█</span>;
}
function Btn({label,color,onClick}){
  return <span onClick={onClick||function(){}} style={{display:"inline-block",background:BG0,border:"1px solid "+(color||DIM),color:color||DIM,fontFamily:F,fontSize:9,padding:"1px 6px",letterSpacing:1,marginRight:3,cursor:"pointer"}}>{label}</span>;
}
function SectionHeader({title,right,color}){
  return(
    <div style={{background:BG2,borderBottom:"1px solid "+BORDER2,padding:"4px 10px",display:"flex",justifyContent:"space-between",alignItems:"center",flexShrink:0}}>
      <span style={{color:color||AMBER,fontFamily:F,fontSize:10,fontWeight:900,letterSpacing:2}}>{title}</span>
      {right&&<span style={{color:DIM,fontFamily:F,fontSize:9,letterSpacing:1}}>{right}</span>}
    </div>
  );
}

/* ── AGENT HUB ── */
function AgentHubBar({claudeActive}){
  return(
    <div style={{background:"#030308",borderBottom:"1px solid #0a0a1a",padding:"3px 14px",display:"flex",gap:0,alignItems:"center",flexShrink:0,overflowX:"auto"}}>
      <span style={{color:"#333",fontFamily:F,fontSize:9,letterSpacing:2,marginRight:12,flexShrink:0}}>AGENT HUB</span>
      {AGENTS.map(function(a,i){
        var live = a.id==="claude" ? (claudeActive?"ACTIVE":"STANDBY") : a.status;
        var c = a.id==="claude" ? (claudeActive?CYAN:MID) : a.color;
        var connected=live==="CONNECTED"||live==="ACTIVE";
        return(
          <div key={a.id} style={{display:"flex",alignItems:"center",gap:5,paddingRight:14,marginRight:14,borderRight:i<AGENTS.length-1?"1px solid #111":"none",flexShrink:0}}>
            <span style={{width:6,height:6,borderRadius:"50%",background:c,display:"inline-block",boxShadow:connected?"0 0 5px "+c:"none"}}/>
            <span style={{color:c,fontFamily:F,fontSize:9,fontWeight:900,letterSpacing:1}}>{a.short}</span>
            <span style={{color:"#333",fontFamily:F,fontSize:8,letterSpacing:1}}>{live}</span>
          </div>
        );
      })}
      <span style={{marginLeft:"auto",color:"#222",fontFamily:F,fontSize:8,letterSpacing:1,flexShrink:0}}>v3.0 · C1 AI-CMD BRIDGE ACTIVE</span>
    </div>
  );
}

/* ── COL 1 ── */
function Portfolio({projects,selectedId,onSelect}){
  var allT=projects.reduce(function(a,p){return a+p.tasks.length;},0);
  var allD=projects.reduce(function(a,p){return a+p.tasks.filter(function(t){return t.status==="Done";}).length;},0);
  var pct=allT?Math.round(allD/allT*100):0;
  return(
    <div style={{display:"flex",flexDirection:"column",height:"100%",overflow:"hidden"}}>
      <SectionHeader title="PORTFOLIO" right={projects.length+" PROJECTS"} color={AMBER}/>
      <div style={{flex:1,overflowY:"auto"}}>
        {projects.map(function(p){
          var sc=statusColor(p.status);
          var sel=selectedId===p.id;
          var done=p.tasks.filter(function(t){return t.status==="Done";}).length;
          var act=p.tasks.filter(function(t){return t.status==="In Progress";}).length;
          var blk=p.tasks.filter(function(t){return t.status==="Blocked";}).length;
          return(
            <div key={p.id} onClick={function(){onSelect(p.id);}}
              style={{borderBottom:"1px solid "+BORDER,padding:"7px 10px",cursor:"pointer",borderLeft:"2px solid "+(sel?p.color:BORDER),background:sel?"#0a0800":BG0}}>
              <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
                <span style={{color:sel?p.color:MID,fontFamily:F,fontWeight:900,fontSize:11,letterSpacing:2}}>{p.short}</span>
                <span style={{color:sc,fontFamily:F,fontSize:9,border:"1px solid "+sc,padding:"0 4px",letterSpacing:1}}>{p.status}</span>
              </div>
              <div style={{color:sel?"#aaa":"#666",fontFamily:F,fontSize:9,marginTop:1}}>{p.name}</div>
              <div style={{color:sel?"#555":"#3a3a3a",fontFamily:F,fontSize:8,marginTop:1,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{p.path}</div>
              <div style={{display:"flex",gap:8,marginTop:3,fontSize:9,fontFamily:F}}>
                <span style={{color:CYAN}}>{done}CLS</span>
                <span style={{color:GREEN}}>{act}ACT</span>
                {blk>0&&<span style={{color:RED}}>{blk}HLT</span>}
                <span style={{color:DIM,marginLeft:"auto"}}>{p.pct}%</span>
              </div>
              <div style={{height:2,background:"#111",marginTop:3,borderRadius:1}}>
                <div style={{height:2,background:p.color,width:p.pct+"%",borderRadius:1}}/>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{borderTop:"2px solid "+BORDER2,flexShrink:0}}>
        <SectionHeader title="SYSTEM VITALS — iMAC M3" color={CYAN}/>
        <div style={{padding:"5px 10px",display:"grid",gridTemplateColumns:"1fr 1fr",gap:3}}>
          {[{l:"CHIP",v:"APPLE M3",c:GREEN},{l:"CORES",v:"8P+4E / 10GPU",c:GREEN},
            {l:"RAM",v:"16 GB LPDDR5",c:CYAN},{l:"DISK",v:"512 GB NVMe",c:CYAN},
            {l:"CPU",v:"12%",c:AMBER},{l:"MEM",v:"68%",c:AMBER},
            {l:"DISPLAY",v:"ULTRAWIDE+RETINA",c:MID},{l:"PORTFOLIO",v:pct+"%",c:pct>70?GREEN:AMBER},
          ].map(function(r){
            return(
              <div key={r.l} style={{display:"flex",justifyContent:"space-between",fontFamily:F,fontSize:9}}>
                <span style={{color:DIM,letterSpacing:1}}>{r.l}</span>
                <span style={{color:r.c,letterSpacing:1}}>{r.v}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ── COL 2 ── */
function CenterPanel({projects,selectedId,onTaskStatus,onAddTask,alerts,onDismissAlert}){
  var p=projects.find(function(p){return p.id===selectedId;});
  return(
    <div style={{display:"flex",flexDirection:"column",height:"100%",overflow:"hidden"}}>
      {p?<ProjectDrillDown project={p} onTaskStatus={onTaskStatus} onAddTask={onAddTask}/>
        :<PipelineOverview projects={projects}/>}
      <AlertsPanel alerts={alerts} onDismiss={onDismissAlert}/>
    </div>
  );
}

function PipelineOverview({projects}){
  var active=projects.filter(function(p){return p.status==="ACTIVE"||p.status==="HALT";});
  return(
    <div style={{flex:1,display:"flex",flexDirection:"column",overflow:"hidden"}}>
      <SectionHeader title="DEV PIPELINE — IN-PROGRESS" color={GREEN}/>
      <div style={{flex:1,overflowY:"auto",padding:"8px 10px"}}>
        {active.map(function(p){
          return(
            <div key={p.id} style={{marginBottom:12,borderLeft:"2px solid "+p.color,paddingLeft:10}}>
              <div style={{display:"flex",justifyContent:"space-between",marginBottom:4}}>
                <span style={{color:p.color,fontFamily:F,fontSize:11,fontWeight:900,letterSpacing:2}}>{p.short} — {p.name}</span>
                <span style={{color:MID,fontFamily:F,fontSize:9}}>{p.pct}%</span>
              </div>
              <div style={{display:"flex",gap:2,marginBottom:3}}>
                {p.phases.map(function(ph,i){
                  var done=i<p.phaseIdx,curr=i===p.phaseIdx;
                  return(
                    <div key={ph} style={{flex:1,background:done?p.color:curr?"#1a1a00":BG2,border:"1px solid "+(done?p.color:curr?AMBER:BORDER2),padding:"3px 0",textAlign:"center"}}>
                      <span style={{color:done?BG0:curr?AMBER:DIM,fontFamily:F,fontSize:7,letterSpacing:1,fontWeight:curr?900:400}}>{ph}</span>
                    </div>
                  );
                })}
              </div>
              {p.blocker
                ?<div style={{fontFamily:F,fontSize:9,color:RED}}>⚠ {p.blocker}</div>
                :<div style={{fontFamily:F,fontSize:9,color:DIM}}>▶ {p.phases[p.phaseIdx]} — NO BLOCKERS</div>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ProjectDrillDown({project,onTaskStatus,onAddTask}){
  var p=project;
  var [addOpen,setAddOpen]=useState(false);
  var [newTxt,setNewTxt]=useState("");
  var [newPh,setNewPh]=useState("");
  var [newSt,setNewSt]=useState("Backlog");
  var [expandedId,setExpandedId]=useState(null);
  function handleAdd(){
    if(!newTxt.trim())return;
    onAddTask(p.id,newTxt,newPh||"GEN",newSt);
    setNewTxt("");setNewPh("");setNewSt("Backlog");setAddOpen(false);
  }
  return(
    <div style={{flex:1,display:"flex",flexDirection:"column",overflow:"hidden"}}>
      <div style={{background:BG2,borderBottom:"2px solid "+p.color,padding:"7px 12px",flexShrink:0}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
          <div>
            <span style={{color:p.color,fontFamily:F,fontWeight:900,fontSize:13,letterSpacing:3}}>{p.short}</span>
            <span style={{color:MID,fontFamily:F,fontSize:10,marginLeft:10}}>{p.name}</span>
          </div>
          <div style={{display:"flex",gap:8,alignItems:"center"}}>
            <span style={{color:p.pct===100?GREEN:AMBER,fontFamily:F,fontSize:12,fontWeight:900}}>{p.pct}%</span>
            <div style={{width:80,height:3,background:"#111",borderRadius:1}}>
              <div style={{height:3,background:p.color,width:p.pct+"%",borderRadius:1}}/>
            </div>
          </div>
        </div>
        <div style={{color:"#333",fontFamily:F,fontSize:8,marginTop:2}}>{p.path}</div>
        <div style={{display:"flex",gap:2,marginTop:5}}>
          {p.phases.map(function(ph,i){
            var done=i<p.phaseIdx,curr=i===p.phaseIdx;
            return(
              <div key={ph} style={{flex:1,background:done?p.color:curr?"#1a1a00":BG0,border:"1px solid "+(done?p.color:curr?AMBER:BORDER2),padding:"2px 0",textAlign:"center"}}>
                <span style={{color:done?BG0:curr?AMBER:DIM,fontFamily:F,fontSize:8,fontWeight:curr?900:400}}>{ph}</span>
              </div>
            );
          })}
        </div>
        {p.blocker&&<div style={{fontFamily:F,fontSize:9,color:RED,marginTop:3}}>⚠ BLOCKER: {p.blocker}</div>}
      </div>
      <div style={{background:BG1,borderBottom:"1px solid "+BORDER2,padding:"4px 10px",display:"flex",gap:6,alignItems:"center",flexShrink:0}}>
        <Btn label="+NEW TASK" color={GREEN} onClick={function(){setAddOpen(!addOpen);}}/>
        <span style={{color:DIM,fontFamily:F,fontSize:9}}>
          {p.tasks.filter(function(t){return t.status==="Done";}).length}CLS &nbsp;
          {p.tasks.filter(function(t){return t.status==="In Progress";}).length}ACT &nbsp;
          {p.tasks.filter(function(t){return t.status==="Blocked";}).length}BLK &nbsp;
          {p.tasks.filter(function(t){return t.status==="Backlog";}).length}QUE
        </span>
      </div>
      {addOpen&&(
        <div style={{background:"#050f00",borderBottom:"1px solid #1a3300",padding:"5px 10px",display:"flex",gap:5,flexWrap:"wrap",flexShrink:0}}>
          <input value={newTxt} onChange={function(e){setNewTxt(e.target.value);}} placeholder="TASK DESCRIPTION"
            style={{flex:2,minWidth:150,background:BG0,border:"1px solid "+BORDER2,color:GREEN,fontFamily:F,fontSize:11,padding:"3px 7px",outline:"none"}}/>
          <input value={newPh} onChange={function(e){setNewPh(e.target.value);}} placeholder="PHASE"
            style={{width:70,background:BG0,border:"1px solid "+BORDER2,color:GREEN,fontFamily:F,fontSize:11,padding:"3px 7px",outline:"none"}}/>
          <select value={newSt} onChange={function(e){setNewSt(e.target.value);}}
            style={{background:BG0,border:"1px solid "+BORDER2,color:GREEN,fontFamily:F,fontSize:11,padding:"3px",outline:"none"}}>
            {STATUSES.map(function(s){return <option key={s}>{s}</option>;})}
          </select>
          <Btn label="SUBMIT" color={GREEN} onClick={handleAdd}/>
          <Btn label="CANCEL" color={DIM} onClick={function(){setAddOpen(false);}}/>
        </div>
      )}
      <div style={{flex:1,display:"grid",gridTemplateColumns:"repeat(4,1fr)",gap:5,padding:"7px 10px",overflowY:"auto"}}>
        {STATUSES.map(function(status){
          var sc=SS[status];
          var tasks=p.tasks.filter(function(t){return t.status===status;});
          return(
            <div key={status} style={{background:sc.bg,border:"1px solid "+sc.border,borderTop:"2px solid "+sc.border,display:"flex",flexDirection:"column"}}>
              <div style={{padding:"3px 7px",borderBottom:"1px solid "+sc.border,display:"flex",justifyContent:"space-between"}}>
                <span style={{color:sc.text,fontFamily:F,fontSize:9,fontWeight:900,letterSpacing:2}}>{sc.tag}</span>
                <span style={{color:sc.text,fontFamily:F,fontSize:9}}>{tasks.length}</span>
              </div>
              <div style={{flex:1,padding:4,overflowY:"auto"}}>
                {tasks.map(function(task){
                  var exp=expandedId===task.id;
                  return(
                    <div key={task.id} onClick={function(){setExpandedId(exp?null:task.id);}}
                      style={{background:exp?"#0f0f0f":BG0,border:"1px solid "+(exp?sc.border:BORDER),padding:"4px 6px",marginBottom:3,cursor:"pointer"}}>
                      <div style={{color:DIM,fontFamily:F,fontSize:8,marginBottom:1}}>{task.phase} #{task.id}</div>
                      <div style={{color:task.status==="Done"?"#333":"#aaa",fontFamily:F,fontSize:10,lineHeight:1.4,textDecoration:task.status==="Done"?"line-through":"none"}}>{task.text}</div>
                      {exp&&(
                        <div style={{display:"flex",gap:2,marginTop:4,flexWrap:"wrap"}}>
                          {STATUSES.filter(function(s){return s!==task.status;}).map(function(s){
                            var c=SS[s];
                            return <Btn key={s} label={"→"+SS[s].tag} color={c.text} onClick={function(e){e.stopPropagation();onTaskStatus(p.id,task.id,s);}}/>;
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function AlertsPanel({alerts,onDismiss}){
  var visible=alerts.filter(function(a){return !a.dismissed;});
  return(
    <div style={{borderTop:"2px solid "+BORDER2,flexShrink:0}}>
      <SectionHeader title="ALERTS & SIGNALS" right={visible.length+" ACTIVE"} color={RED}/>
      <div style={{maxHeight:110,overflowY:"auto"}}>
        {visible.length===0&&<div style={{padding:"6px 10px",color:DIM,fontFamily:F,fontSize:9,letterSpacing:1}}>NO ACTIVE ALERTS — ALL CLEAR</div>}
        {visible.map(function(a){
          var c=a.lvl==="HALT"?RED:a.lvl==="WARN"?AMBER:CYAN;
          return(
            <div key={a.id} style={{padding:"4px 10px",borderBottom:"1px solid "+BORDER,display:"flex",gap:7,alignItems:"flex-start"}}>
              <span style={{color:c,fontFamily:F,fontSize:9,fontWeight:900,border:"1px solid "+c,padding:"0 4px",flexShrink:0,letterSpacing:1}}>{a.lvl}</span>
              <span style={{color:MID,fontFamily:F,fontSize:9,lineHeight:1.4,flex:1}}>{a.msg}</span>
              <Btn label="DISMISS"  color={DIM} onClick={function(){onDismiss(a.id);}}/>
              <Btn label="ESCALATE" color={RED} onClick={function(){onDismiss(a.id);}}/>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* ── COL 3 ── */
function RightPanel(){
  var [expandedPid,setExpandedPid]=useState(null);
  return(
    <div style={{display:"flex",flexDirection:"column",height:"100%",overflow:"hidden"}}>
      <SectionHeader title="LIVE PROCESSES" right={PROCESSES.filter(function(p){return p.status==="RUNNING";}).length+" RUNNING"} color={CYAN}/>
      <div style={{overflowY:"auto",maxHeight:220,flexShrink:0}}>
        <table style={{width:"100%",borderCollapse:"collapse",fontFamily:F,fontSize:9}}>
          <thead>
            <tr style={{background:BG2,borderBottom:"1px solid "+BORDER2}}>
              {["PID","TYPE","PROCESS","CPU","MEM","UPTIME","STATUS","AGT","ACT"].map(function(h){
                return <th key={h} style={{padding:"3px 6px",textAlign:"left",color:DIM,letterSpacing:1,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{h}</th>;
              })}
            </tr>
          </thead>
          <tbody>
            {PROCESSES.map(function(p,i){
              var sc=statusColor(p.status);
              var exp=expandedPid===p.pid;
              return([
                <tr key={p.pid} onClick={function(){setExpandedPid(exp?null:p.pid);}}
                  style={{background:exp?BG3:i%2===0?BG1:BG2,borderBottom:"1px solid "+BORDER,cursor:"pointer"}}>
                  <td style={{padding:"3px 6px",color:DIM,borderRight:"1px solid "+BORDER}}>{p.pid}</td>
                  <td style={{padding:"3px 6px",color:MID,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{p.type}</td>
                  <td style={{padding:"3px 6px",color:exp?"#ccc":"#999",borderRight:"1px solid "+BORDER,maxWidth:130,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{p.name}</td>
                  <td style={{padding:"3px 6px",color:parseFloat(p.cpu)>2?AMBER:GREEN,borderRight:"1px solid "+BORDER}}>{p.cpu}</td>
                  <td style={{padding:"3px 6px",color:CYAN,borderRight:"1px solid "+BORDER}}>{p.mem}</td>
                  <td style={{padding:"3px 6px",color:DIM,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{p.uptime}</td>
                  <td style={{padding:"3px 6px",borderRight:"1px solid "+BORDER}}>
                    <span style={{color:sc,border:"1px solid "+sc,padding:"0 4px",fontSize:8,letterSpacing:1}}>{p.status}</span>
                  </td>
                  <td style={{padding:"3px 6px",borderRight:"1px solid "+BORDER}}>
                    <span style={{color:GREEN,fontFamily:F,fontSize:8}}>DC</span>
                  </td>
                  <td style={{padding:"3px 6px"}}><Btn label="▼" color={DIM}/><Btn label="↺" color={AMBER}/></td>
                </tr>,
                exp&&(
                  <tr key={p.pid+"-log"} style={{background:"#050500"}}>
                    <td colSpan={9} style={{padding:"5px 12px",borderBottom:"1px solid "+BORDER}}>
                      <div style={{color:AMBER,fontFamily:F,fontSize:8,marginBottom:2}}>LOG — {p.script}</div>
                      {p.logs.map(function(l,li){
                        return <div key={li} style={{color:l.includes("ERROR")||l.includes("error")?RED:DIM,fontFamily:F,fontSize:8}}>{l}</div>;
                      })}
                    </td>
                  </tr>
                )
              ]);
            })}
          </tbody>
        </table>
      </div>
      <div style={{borderTop:"2px solid "+BORDER2,flex:1,display:"flex",flexDirection:"column",overflow:"hidden"}}>
        <SectionHeader title="AUTOMATION REGISTRY" right={AUTOMATIONS.length+" REGISTERED"} color={AMBER}/>
        <div style={{flex:1,overflowY:"auto"}}>
          <table style={{width:"100%",borderCollapse:"collapse",fontFamily:F,fontSize:9}}>
            <thead>
              <tr style={{background:BG2,borderBottom:"1px solid "+BORDER2}}>
                {["ID","NAME","TRIGGER","TYPE","LAST RUN","STATUS","AGT","ACTIONS"].map(function(h){
                  return <th key={h} style={{padding:"3px 6px",textAlign:"left",color:DIM,letterSpacing:1,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{h}</th>;
                })}
              </tr>
            </thead>
            <tbody>
              {AUTOMATIONS.map(function(a,i){
                var sc=statusColor(a.status);
                var agc=a.agent==="DC"?GREEN:a.agent==="CURSOR"?CYAN:a.agent==="HA"?RED:AMBER;
                return(
                  <tr key={a.id} style={{background:i%2===0?BG1:BG2,borderBottom:"1px solid "+BORDER}}>
                    <td style={{padding:"3px 6px",color:DIM,borderRight:"1px solid "+BORDER}}>{a.id}</td>
                    <td style={{padding:"3px 6px",color:"#bbb",borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{a.name}</td>
                    <td style={{padding:"3px 6px",color:MID,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{a.trigger}</td>
                    <td style={{padding:"3px 6px",borderRight:"1px solid "+BORDER}}>
                      <span style={{color:CYAN,border:"1px solid #1a4a4a",padding:"0 4px",fontSize:8,letterSpacing:1}}>{a.type}</span>
                    </td>
                    <td style={{padding:"3px 6px",color:DIM,borderRight:"1px solid "+BORDER,whiteSpace:"nowrap"}}>{a.lastRun}</td>
                    <td style={{padding:"3px 6px",borderRight:"1px solid "+BORDER}}>
                      <span style={{color:sc,border:"1px solid "+sc,padding:"0 4px",fontSize:8,letterSpacing:1}}>{a.status}</span>
                    </td>
                    <td style={{padding:"3px 6px",borderRight:"1px solid "+BORDER}}>
                      <span style={{color:agc,fontFamily:F,fontSize:8,letterSpacing:1}}>{a.agent}</span>
                    </td>
                    <td style={{padding:"3px 6px"}}>
                      <Btn label="RUN" color={GREEN}/><Btn label="EDIT" color={AMBER}/><Btn label="OFF" color={RED}/>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

/* ── GMC PANEL ── */
function GMCPanel(){
  var d=GMC_DATA;var pc=d.regime.color;
  return(
    <div style={{background:BG1,borderTop:"2px solid #f97316",flexShrink:0}}>
      <div style={{background:BG2,borderBottom:"1px solid "+BORDER2,padding:"4px 12px",display:"flex",alignItems:"center",justifyContent:"space-between"}}>
        <span style={{color:"#f97316",fontFamily:F,fontSize:10,fontWeight:900,letterSpacing:2}}>GMC — GIOVANNINI MARE CAPITAL  ·  PRIVATE SINGLE-FAMILY OFFICE</span>
        <span style={{color:DIM,fontFamily:F,fontSize:9}}>MOCK DATA</span>
      </div>
      <div style={{display:"grid",gridTemplateColumns:"180px 1fr 1fr 1fr"}}>
        <div style={{borderRight:"1px solid "+BORDER2,padding:"7px 12px",display:"flex",flexDirection:"column",justifyContent:"center"}}>
          <div style={{color:DIM,fontFamily:F,fontSize:8,letterSpacing:2,marginBottom:4}}>MACRO REGIME</div>
          <div style={{color:pc,fontFamily:F,fontSize:16,fontWeight:900,letterSpacing:3,border:"1px solid "+pc,padding:"4px 10px",textAlign:"center"}}>{d.regime.label}</div>
          <div style={{color:pc,fontFamily:F,fontSize:8,marginTop:3,letterSpacing:1,textAlign:"center",opacity:0.7}}>{d.regime.sub}</div>
          <div style={{marginTop:8}}>
            <div style={{color:DIM,fontFamily:F,fontSize:8,marginBottom:3}}>PRESERVATION SCORE</div>
            <div style={{display:"flex",alignItems:"center",gap:6}}>
              <div style={{flex:1,height:4,background:"#111",borderRadius:1}}>
                <div style={{height:4,background:d.score>70?GREEN:AMBER,width:d.score+"%",borderRadius:1}}/>
              </div>
              <span style={{color:GREEN,fontFamily:F,fontSize:10,fontWeight:900}}>{d.score}%</span>
            </div>
          </div>
        </div>
        <div style={{borderRight:"1px solid "+BORDER2,padding:"6px 10px"}}>
          <div style={{color:DIM,fontFamily:F,fontSize:8,letterSpacing:2,marginBottom:4}}>MARKET RATES</div>
          <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:3}}>
            {d.rates.map(function(r){
              var uc=r.up===null?DIM:r.up?GREEN:RED;
              var arr=r.up===null?"—":r.up?"▲":"▼";
              return(
                <div key={r.pair} style={{background:BG0,border:"1px solid "+BORDER,padding:"3px 6px"}}>
                  <div style={{color:DIM,fontFamily:F,fontSize:8}}>{r.pair}</div>
                  <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline",marginTop:1}}>
                    <span style={{color:"#ccc",fontFamily:F,fontSize:11,fontWeight:700}}>{r.val}</span>
                    <span style={{color:uc,fontFamily:F,fontSize:8}}>{arr} {r.delta}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        <div style={{borderRight:"1px solid "+BORDER2,padding:"6px 10px"}}>
          <div style={{color:DIM,fontFamily:F,fontSize:8,letterSpacing:2,marginBottom:4}}>PORTFOLIO ALLOCATION</div>
          {d.allocation.map(function(a){
            return(
              <div key={a.label} style={{marginBottom:4}}>
                <div style={{display:"flex",justifyContent:"space-between",fontFamily:F,fontSize:9,marginBottom:2}}>
                  <span style={{color:a.color}}>{a.label}</span>
                  <span style={{color:"#777"}}>{a.pct}%</span>
                </div>
                <div style={{height:3,background:"#111",borderRadius:1}}>
                  <div style={{height:3,background:a.color,width:a.pct+"%",borderRadius:1,opacity:0.8}}/>
                </div>
              </div>
            );
          })}
        </div>
        <div style={{padding:"6px 10px"}}>
          <div style={{color:DIM,fontFamily:F,fontSize:8,letterSpacing:2,marginBottom:4}}>MACRO SIGNALS</div>
          {d.signals.map(function(s){
            var c=statusColor(s.status);
            return(
              <div key={s.label} style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:5,background:BG0,border:"1px solid "+BORDER,padding:"3px 7px"}}>
                <span style={{color:MID,fontFamily:F,fontSize:9}}>{s.label}</span>
                <span style={{color:"#aaa",fontFamily:F,fontSize:9,fontWeight:700}}>{s.val}</span>
                <span style={{color:c,border:"1px solid "+c,fontFamily:F,fontSize:8,padding:"0 4px"}}>{s.status}</span>
              </div>
            );
          })}
          <div style={{marginTop:4,padding:"4px 7px",background:"#0a0500",border:"1px solid #2a1500"}}>
            <div style={{color:DIM,fontFamily:F,fontSize:8}}>NEXT ACTION</div>
            <div style={{color:AMBER,fontFamily:F,fontSize:9,marginTop:1}}>MAINTAIN CASH — AWAIT SELIC SIGNAL</div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── LIFE OS PANEL ── */
function LifeOSPanel({onLog}){
  var [status,setStatus]=useState("OFFLINE");
  var sc=status==="RUNNING"?GREEN:status==="ERROR"?RED:MID;
  function launch(mod){setStatus("RUNNING");if(onLog)onLog("LIFE OS","LAUNCH → "+mod.label);}
  function launchAll(){setStatus("RUNNING");if(onLog)onLog("LIFE OS","FULL LAUNCH → localhost:8000");}
  function stop(){setStatus("OFFLINE");if(onLog)onLog("LIFE OS","SERVER STOPPED");}
  return(
    <div style={{background:BG1,borderTop:"2px solid "+CYAN,flexShrink:0}}>
      <div style={{background:BG2,borderBottom:"1px solid "+BORDER2,padding:"4px 12px",display:"flex",alignItems:"center",justifyContent:"space-between"}}>
        <div style={{display:"flex",alignItems:"center",gap:10}}>
          <span style={{color:CYAN,fontFamily:F,fontSize:10,fontWeight:900,letterSpacing:2}}>LIFE OS</span>
          <span style={{color:DIM,fontFamily:F,fontSize:9}}>DJANGO · localhost:8000</span>
          <span style={{width:6,height:6,borderRadius:"50%",background:sc,display:"inline-block",boxShadow:status==="RUNNING"?"0 0 5px "+GREEN:"none"}}/>
          <span style={{color:sc,fontFamily:F,fontSize:9,letterSpacing:1}}>{status}</span>
        </div>
        <div style={{display:"flex",gap:5,alignItems:"center"}}>
          <span onClick={launchAll} style={{background:"#0a1a00",border:"1px solid "+GREEN,color:GREEN,fontFamily:F,fontSize:9,padding:"2px 10px",cursor:"pointer",letterSpacing:1,fontWeight:900}}>▶ START</span>
          <span onClick={stop}      style={{background:"#1a0000",border:"1px solid "+RED,  color:RED,  fontFamily:F,fontSize:9,padding:"2px 10px",cursor:"pointer",letterSpacing:1}}>■ STOP</span>
          <span style={{background:"#0a0a00",border:"1px solid "+AMBER,color:AMBER,fontFamily:F,fontSize:9,padding:"2px 10px",cursor:"pointer",letterSpacing:1}}>↺ RESTART</span>
          <span style={{background:BG0,border:"1px solid "+BORDER2,color:MID,fontFamily:F,fontSize:9,padding:"2px 10px",cursor:"pointer",letterSpacing:1}}>LOGS</span>
        </div>
      </div>
      <div style={{display:"flex"}}>
        {LIFEOS_MODULES.map(function(mod,i){
          var msc=mod.status==="RUNNING"||mod.status==="ACTIVE"?GREEN:mod.status==="IDLE"?MID:AMBER;
          return(
            <div key={mod.id} onClick={function(){launch(mod);}}
              style={{flex:1,borderRight:i<LIFEOS_MODULES.length-1?"1px solid "+BORDER2:"none",
                padding:"7px 10px",cursor:"pointer",background:BG0,display:"flex",flexDirection:"column",gap:3}}
              onMouseEnter={function(e){e.currentTarget.style.background=BG2;}}
              onMouseLeave={function(e){e.currentTarget.style.background=BG0;}}>
              <div style={{display:"flex",alignItems:"center",justifyContent:"space-between"}}>
                <span style={{fontSize:14}}>{mod.icon}</span>
                <span style={{color:msc,fontFamily:F,fontSize:8,border:"1px solid "+msc,padding:"0 3px",letterSpacing:1}}>{mod.status}</span>
              </div>
              <div style={{color:CYAN,fontFamily:F,fontSize:9,fontWeight:900,letterSpacing:1}}>{mod.label}</div>
              <div style={{color:"#333",fontFamily:F,fontSize:8,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{mod.path}</div>
              <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginTop:2}}>
                <span style={{color:"#1a5200",fontFamily:F,fontSize:8,border:"1px solid #1a5200",padding:"0 4px"}}>OPEN →</span>
                <span style={{color:"#333",fontFamily:F,fontSize:8}}>{mod.key}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* ── AI CMD RESPONSE PANE ── */
function AICmdPane({response,loading,theme}){
  var tc=theme?theme.primary:AMBER;
  if(!response&&!loading)return null;
  return(
    <div style={{background:"#020a02",borderTop:"1px solid #0a2a0a",borderBottom:"1px solid #0a2a0a",padding:"6px 14px",flexShrink:0,maxHeight:120,overflowY:"auto"}}>
      <div style={{display:"flex",gap:8,alignItems:"flex-start"}}>
        <span style={{color:CYAN,fontFamily:F,fontSize:9,fontWeight:900,letterSpacing:1,flexShrink:0,marginTop:1}}>CLAUDE&gt;</span>
        {loading
          ? <span style={{color:DIM,fontFamily:F,fontSize:9,letterSpacing:1}}>PROCESSING <Blink color={CYAN}/></span>
          : <span style={{color:"#aaa",fontFamily:F,fontSize:9,lineHeight:1.6,whiteSpace:"pre-wrap",letterSpacing:0.5}}>{response}</span>
        }
      </div>
    </div>
  );
}

/* ── BOTTOM BAR ── */
function BottomBar({log,theme,onCommand,loading}){
  var [cmd,setCmd]=useState("");
  var logRef=useRef(null);
  var tc=theme?theme.primary:AMBER;
  useEffect(function(){if(logRef.current)logRef.current.scrollLeft=logRef.current.scrollWidth;},[log]);

  function submit(){
    if(!cmd.trim()||loading)return;
    onCommand(cmd);
    setCmd("");
  }

  return(
    <div style={{background:BG1,borderTop:"2px solid "+tc,flexShrink:0}}>
      <div style={{background:BG0,borderBottom:"1px solid "+BORDER2,padding:"3px 12px",display:"flex",gap:5,alignItems:"center",flexWrap:"wrap"}}>
        <span style={{color:DIM,fontFamily:F,fontSize:9,letterSpacing:2,marginRight:4}}>QUICK:</span>
        {QUICK_ACTIONS.map(function(a){
          return(
            <span key={a} onClick={function(){onCommand(a.toLowerCase());}}
              style={{background:BG2,border:"1px solid "+BORDER2,color:MID,fontFamily:F,fontSize:9,padding:"2px 8px",letterSpacing:1,cursor:"pointer"}}
              onMouseEnter={function(e){e.currentTarget.style.color=tc;e.currentTarget.style.borderColor=tc;}}
              onMouseLeave={function(e){e.currentTarget.style.color=MID;e.currentTarget.style.borderColor=BORDER2;}}>
              {a}
            </span>
          );
        })}
      </div>
      <div style={{display:"flex",alignItems:"center",gap:10,padding:"5px 12px"}}>
        <span style={{color:tc,fontFamily:F,fontWeight:900,fontSize:13,flexShrink:0}}>CMD&gt;</span>
        <input value={cmd}
          onChange={function(e){setCmd(e.target.value);}}
          onKeyDown={function(e){if(e.key==="Enter")submit();}}
          placeholder="add task / what is blocked / git status ffa / run desk-sanity / ff launch / kill idle ..."
          style={{flex:"0 0 480px",background:"transparent",border:"none",borderBottom:"1px solid "+(loading?tc:BORDER2),
            color:GREEN,fontFamily:F,fontSize:11,padding:"3px 0",outline:"none",letterSpacing:1,
            opacity:loading?0.5:1}}
          disabled={loading}
        />
        <button onClick={submit} disabled={loading}
          style={{background:loading?"#111":tc==="AMBER"?"#1a0f00":"#001a33",border:"1px solid "+tc,color:tc,
            fontFamily:F,fontSize:9,padding:"3px 12px",cursor:loading?"default":"pointer",letterSpacing:2,fontWeight:900,opacity:loading?0.5:1}}>
          {loading?"WAIT":"EXEC"}
        </button>
        {loading&&<Blink color={CYAN}/>}
        <span style={{color:DIM,fontFamily:F,fontSize:9,letterSpacing:2,marginLeft:6,flexShrink:0}}>LOG:</span>
        <div ref={logRef} style={{flex:1,overflowX:"auto",whiteSpace:"nowrap",fontFamily:F,fontSize:9,display:"flex",gap:14,alignItems:"center"}}>
          {log.map(function(l,i){
            var c=l.lvl==="err"?RED:l.lvl==="ai"?CYAN:DIM;
            return(
              <span key={i} style={{color:c,flexShrink:0}}>
                <span style={{color:"#333"}}>{l.t}</span>
                {" "}<span style={{color:tc}}>[{l.src}]</span>
                {" "}{l.msg}
              </span>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ── ROOT ── */
export default function App(){
  var [projects,setProjects]=useState(INIT_PROJECTS);
  var [selectedId,setSelectedId]=useState(null);
  var [alerts,setAlerts]=useState(INIT_ALERTS);
  var [log,setLog]=useState(INIT_LOG);
  var [fontSize,setFontSize]=useState(3);
  var [themeKey,setThemeKey]=useState("amber");
  var [aiResponse,setAiResponse]=useState("");
  var [aiLoading,setAiLoading]=useState(false);
  var theme=THEMES[themeKey];
  var base=9+fontSize;
  var scale=function(n){return (n+fontSize)+"px";};

  function addLog(src,msg,lvl){
    var d=new Date();
    var t=pad(d.getHours())+":"+pad(d.getMinutes())+":"+pad(d.getSeconds());
    setLog(function(prev){return prev.concat([{t:t,src:src,msg:msg,lvl:lvl||"ok"}]);});
  }

  function handleSelect(id){
    setSelectedId(function(prev){return prev===id?null:id;});
    var p=INIT_PROJECTS.find(function(p){return p.id===id;});
    if(p)addLog("DRILL","OPENED "+p.short);
  }
  function handleTaskStatus(pid,tid,status){
    setProjects(function(prev){return prev.map(function(p){
      if(p.id!==pid)return p;
      var updated=p.tasks.map(function(t){return t.id===tid?Object.assign({},t,{status:status}):t;});
      var done=updated.filter(function(t){return t.status==="Done";}).length;
      return Object.assign({},p,{tasks:updated,pct:updated.length?Math.round(done/updated.length*100):0});
    });});
    addLog("TASK","#"+tid+" → "+status.toUpperCase());
  }
  function handleAddTask(pid,text,phase,status){
    setProjects(function(prev){return prev.map(function(p){
      if(p.id!==pid)return p;
      var updated=p.tasks.concat([{id:uid++,text:text,phase:phase,status:status}]);
      var done=updated.filter(function(t){return t.status==="Done";}).length;
      return Object.assign({},p,{tasks:updated,pct:updated.length?Math.round(done/updated.length*100):0});
    });});
    addLog("TASK","NEW → "+text.substring(0,28).toUpperCase());
  }
  function handleDismissAlert(id){
    setAlerts(function(prev){return prev.map(function(a){return a.id===id?Object.assign({},a,{dismissed:true}):a;});});
    addLog("ALERT","DISMISSED #"+id);
  }

  async function handleCommand(cmd){
    if(!cmd.trim())return;
    setAiLoading(true);
    setAiResponse("");
    addLog("CMD",cmd.substring(0,40).toUpperCase(),"ai");

    var snapshot=projects.map(function(p){
      return {id:p.id,short:p.short,name:p.name,status:p.status,pct:p.pct,
        phase:p.phases[p.phaseIdx],blocker:p.blocker||null,
        tasks:p.tasks.map(function(t){return {id:t.id,text:t.text,phase:t.phase,status:t.status};})};
    });

    var systemPrompt=[
      "You are the AI command processor for FOKS TERMINAL v3.0 — the personal ops terminal of Eduardo Giovannini (Eddie), an independent developer based in Cabedelo-PB, Brazil.",
      "You have full context of his projects, tasks, and system state.",
      "",
      "CONNECTED AGENTS: Desktop Commander (DC) — shell/filesystem ops | Cursor — code editor | Claude API — AI | IFTTT — automations | HA — Home Assistant (ERROR state)",
      "",
      "CURRENT PROJECT STATE:",
      JSON.stringify(snapshot,null,2),
      "",
      "AUTOMATIONS: workspace_launch.sh, ff-sync.zsh, ff-backup.zsh, desk_sanity_check.zsh, mac_inventory_audit.sh, preflight_validate.sh, GMC_Launch.command",
      "KEY PATHS: ~/dev, ~/AUTOGIO, ~/foks, ~/FuloFilo",
      "ACTIVE BLOCKER: HA Tuya 0-device auth failure — re-auth via Smart Life required",
      "",
      "YOUR JOB:",
      "1. Understand the user's natural language command.",
      "2. If it's a task/project action (add task, update status, query state), respond in JSON with action + message.",
      "3. If it's a shell/DC command (git status, run script, check processes), describe exactly what DC would execute and what output to expect.",
      "4. If it's a question, answer concisely and precisely as a senior dev ops assistant.",
      "5. Always be terse, terminal-style. No markdown. No fluff. Max 4 sentences.",
      "",
      "For task actions respond with JSON only:",
      '{"action":"add_task"|"update_status"|"summary"|"next_task","projectId":"<id>","taskId":<n>,"text":"<text>","phase":"<ph>","status":"Backlog|In Progress|Done|Blocked","message":"<reply>"}',
      "",
      "For everything else respond with plain terminal-style text.",
    ].join("\n");

    try{
      var res=await fetch("https://api.anthropic.com/v1/messages",{
        method:"POST",
        headers:{"Content-Type":"application/json"},
        body:JSON.stringify({
          model:"claude-sonnet-4-20250514",
          max_tokens:600,
          system:systemPrompt,
          messages:[{role:"user",content:cmd}]
        })
      });
      var data=await res.json();
      var raw=(data.content&&data.content[0]&&data.content[0].text)||"NO RESPONSE";
      var clean=raw.replace(/```json|```/g,"").trim();

      // try JSON action
      try{
        var parsed=JSON.parse(clean);
        if(parsed.action==="add_task"&&parsed.projectId&&parsed.text){
          handleAddTask(parsed.projectId,parsed.text,parsed.phase||"GEN",parsed.status||"Backlog");
          setSelectedId(parsed.projectId);
        } else if(parsed.action==="update_status"&&parsed.projectId&&parsed.taskId){
          handleTaskStatus(parsed.projectId,parsed.taskId,parsed.status);
          setSelectedId(parsed.projectId);
        }
        setAiResponse(parsed.message||clean);
        addLog("CLAUDE",(parsed.message||"ACTION EXECUTED").substring(0,50).toUpperCase(),"ai");
      } catch(_){
        // plain text response
        setAiResponse(clean);
        addLog("CLAUDE",clean.substring(0,50).toUpperCase(),"ai");
      }
    } catch(e){
      setAiResponse("ERR: API CALL FAILED — "+e.message);
      addLog("CLAUDE","API ERROR","err");
    }
    setAiLoading(false);
  }

  var allTasks=projects.reduce(function(a,p){return a+p.tasks.length;},0);
  var allDone=projects.reduce(function(a,p){return a+p.tasks.filter(function(t){return t.status==="Done";}).length;},0);
  var pct=allTasks?Math.round(allDone/allTasks*100):0;
  var activeAlerts=alerts.filter(function(a){return !a.dismissed;}).length;
  var running=PROCESSES.filter(function(p){return p.status==="RUNNING";}).length;

  return(
    <div style={{background:theme.bg0,height:"100vh",display:"flex",flexDirection:"column",color:"#ccc",fontFamily:F,overflow:"hidden",fontSize:base+"px"}}>
      <style>{`
        * { font-size: inherit !important; }
        [style*="font-size:7px"]  { font-size: ${scale(7)}  !important; }
        [style*="font-size:8px"]  { font-size: ${scale(8)}  !important; }
        [style*="font-size:9px"]  { font-size: ${scale(9)}  !important; }
        [style*="font-size:10px"] { font-size: ${scale(10)} !important; }
        [style*="font-size:11px"] { font-size: ${scale(11)} !important; }
        [style*="font-size:12px"] { font-size: ${scale(12)} !important; }
        [style*="font-size:13px"] { font-size: ${scale(13)} !important; }
        [style*="font-size:14px"] { font-size: ${scale(14)} !important; }
        [style*="font-size:16px"] { font-size: ${scale(16)} !important; }
        [style*="font-size:18px"] { font-size: ${scale(18)} !important; }
      `}</style>

      {/* TOP BAR */}
      <div style={{background:theme.top,borderBottom:"1px solid "+theme.topAccent,padding:"3px 14px",display:"flex",justifyContent:"space-between",alignItems:"center",flexShrink:0}}>
        <div style={{color:theme.topAccent,fontWeight:900,fontSize:12,letterSpacing:2,fontFamily:F}}>
          FOKS TERMINAL v3.0  ·  GIOVANNINI PRIVATE OPS  ·  CABEDELO-PB  ·  iMAC M3  ·  C1 BRIDGE
        </div>
        <div style={{display:"flex",gap:10,alignItems:"center"}}>
          <Clock/>
          <div style={{display:"flex",alignItems:"center",gap:4,border:"1px solid "+theme.border2,padding:"1px 7px"}}>
            <span style={{color:theme.topText,fontFamily:F,fontSize:9,opacity:0.6}}>FONT</span>
            <button onClick={function(){setFontSize(function(v){return Math.max(-4,v-1);});}}
              style={{background:"transparent",border:"none",color:theme.topAccent,fontFamily:F,fontSize:14,cursor:"pointer",padding:"0 3px",lineHeight:1}}>−</button>
            <span style={{color:theme.topAccent,fontFamily:F,fontSize:10,fontWeight:900,minWidth:22,textAlign:"center"}}>{base}px</span>
            <button onClick={function(){setFontSize(function(v){return Math.min(10,v+1);});}}
              style={{background:"transparent",border:"none",color:theme.topAccent,fontFamily:F,fontSize:14,cursor:"pointer",padding:"0 3px",lineHeight:1}}>+</button>
          </div>
          <div style={{display:"flex",gap:3}}>
            {Object.keys(THEMES).map(function(k){
              var th=THEMES[k];var active=themeKey===k;
              return(
                <button key={k} onClick={function(){setThemeKey(k);}}
                  style={{background:active?th.topAccent:"transparent",border:"1px solid "+(active?th.topAccent:theme.border2),
                    color:active?th.bg0:theme.topText,fontFamily:F,fontSize:9,padding:"2px 8px",cursor:"pointer",letterSpacing:1,fontWeight:active?900:400}}>
                  {th.name}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <AgentHubBar claudeActive={aiLoading}/>

      {/* TICKER */}
      <div style={{background:theme.tickerBg,borderBottom:"1px solid "+theme.tickerBorder,padding:"3px 14px",display:"flex",overflowX:"auto",flexShrink:0,alignItems:"center"}}>
        {projects.map(function(p){
          var c=p.pct===100?GREEN:p.status==="HALT"?RED:p.pct>50?AMBER:MID;
          return(
            <span key={p.id} onClick={function(){handleSelect(p.id);}}
              style={{fontFamily:F,fontSize:10,color:c,fontWeight:700,letterSpacing:1,paddingRight:14,borderRight:"1px solid "+theme.tickerBorder,marginRight:14,whiteSpace:"nowrap",cursor:"pointer"}}>
              {p.short} <span style={{color:p.color}}>{p.pct}%</span>
            </span>
          );
        })}
        <span style={{fontFamily:F,fontSize:10,color:DIM,letterSpacing:1,marginLeft:"auto",whiteSpace:"nowrap"}}>
          PORTFOLIO <span style={{color:pct>70?GREEN:AMBER,fontWeight:900}}>{pct}%</span>
          {"  "}ALERTS <span style={{color:activeAlerts>0?RED:GREEN,fontWeight:900}}>{activeAlerts}</span>
          {"  "}PROCS <span style={{color:GREEN,fontWeight:900}}>{running} RUN</span>
          {"  "}CLAUDE <span style={{color:aiLoading?CYAN:DIM,fontWeight:900}}>{aiLoading?"ACTIVE":"STANDBY"}</span>
        </span>
      </div>

      {/* STAT ROW */}
      <div style={{background:theme.bg2,borderBottom:"1px solid "+theme.border,display:"flex",flexShrink:0}}>
        {[
          {l:"PROJECTS",   v:projects.length,c:MID},
          {l:"ACTIVE",     v:projects.filter(function(p){return p.status==="ACTIVE";}).length,c:GREEN},
          {l:"HALTED",     v:projects.filter(function(p){return p.status==="HALT";}).length,c:RED},
          {l:"COMPLETE",   v:projects.filter(function(p){return p.status==="COMPLETE";}).length,c:CYAN},
          {l:"TOTAL TASKS",v:allTasks,c:MID},
          {l:"CLOSED",     v:allDone,c:GREEN},
          {l:"COMPLETION", v:pct+"%",c:AMBER},
          {l:"PROCESSES",  v:running+" RUN",c:GREEN},
          {l:"AUTOMATIONS",v:AUTOMATIONS.filter(function(a){return a.status==="ACTIVE";}).length+" ON",c:CYAN},
          {l:"ALERTS",     v:activeAlerts,c:activeAlerts>0?RED:GREEN},
        ].map(function(s){
          return(
            <div key={s.l} style={{flex:1,borderRight:"1px solid "+theme.border,padding:"4px 8px",textAlign:"center"}}>
              <div style={{color:DIM,fontSize:8,letterSpacing:1,marginBottom:1,fontFamily:F}}>{s.l}</div>
              <div style={{color:s.c,fontSize:14,fontWeight:900,letterSpacing:2,fontFamily:F}}>{s.v}</div>
            </div>
          );
        })}
      </div>

      {/* 3-COL MAIN */}
      <div style={{flex:1,display:"grid",gridTemplateColumns:"240px 1fr 1fr",overflow:"hidden"}}>
        <div style={{borderRight:"1px solid "+theme.border2,overflow:"hidden",display:"flex",flexDirection:"column"}}>
          <Portfolio projects={projects} selectedId={selectedId} onSelect={handleSelect}/>
        </div>
        <div style={{borderRight:"1px solid "+theme.border2,overflow:"hidden",display:"flex",flexDirection:"column"}}>
          <CenterPanel projects={projects} selectedId={selectedId} onTaskStatus={handleTaskStatus} onAddTask={handleAddTask} alerts={alerts} onDismissAlert={handleDismissAlert}/>
        </div>
        <div style={{overflow:"hidden",display:"flex",flexDirection:"column"}}>
          <RightPanel/>
        </div>
      </div>

      <GMCPanel/>
      <LifeOSPanel onLog={addLog}/>
      <AICmdPane response={aiResponse} loading={aiLoading} theme={theme}/>
      <BottomBar log={log} theme={theme} onCommand={handleCommand} loading={aiLoading}/>
    </div>
  );
}
