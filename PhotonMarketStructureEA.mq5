//+------------------------------------------------------------------+
//|                                    PhotonMarketStructureEA.mq5   |
//|  Multi-timeframe market-structure trading bot                     |
//|                                                                   |
//|  Top-down flow:                                                   |
//|    1. HTF (default H1) -> macro bias + zones                      |
//|    2. LTF (chart TF, e.g. M1) -> precise entry inside bias        |
//|                                                                   |
//|  Structure features: swings, BOS, CHoCH, Order Blocks, FVGs,      |
//|  Liquidity sweeps.                                                |
//|                                                                   |
//|  Trade management: BE at +1R, ATR trailing after BE, optional     |
//|  partial close at 1R, TP either RR multiple or next HTF swing.    |
//|                                                                   |
//|  Self-learning: every closed trade is journaled with its setup    |
//|  context (HTF-agree, FVG, sweep, session). Rolling win-rate per   |
//|  setup bucket is tracked and weak buckets are auto-suppressed.    |
//|  Journal persists to a CSV file in the terminal data folder.      |
//|                                                                   |
//|  Symbol presets auto-detect US30 / US100 / US500 / XAUUSD with    |
//|  sensible spread caps and SL sizing.                              |
//+------------------------------------------------------------------+
#property copyright "Market Structure Assistant"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/DealInfo.mqh>

//============================== INPUTS ===========================
input group "=== Kill switch ==="
input bool   AlertsOnly         = true;     // true = signal only, no live orders
input bool   ShowChartMarkup    = true;

input group "=== Multi-timeframe analysis ==="
input bool             UseHTFBias         = true;
input ENUM_TIMEFRAMES  HTFPeriod          = PERIOD_H1;
input int              HTFAnalysisBars    = 800;
input int              HTFSwingLength     = 5;
input bool             RequireHTFAgree    = true;  // hard filter when true
input bool             PreferHTFZones     = true;  // soft preference for entries inside HTF zones

input group "=== Structure (LTF / chart TF) ==="
input int    SwingLength        = 5;
input int    AnalysisBars       = 1500;
input int    MaxZoneAgeBars     = 250;
input bool   UseCHoCH           = true;
input bool   UseOrderBlocks     = true;
input bool   UseFVG             = true;
input bool   UseLiquiditySweep  = true;

input group "=== Entry ==="
input bool   EntryOnOBRetrace   = true;
input bool   RequireFVGInOB     = false;
input bool   RequireSweep       = false;
input double MinRewardToRisk    = 2.0;      // skip if computed RR below this
input bool   TPFromHTFSwing     = true;     // TP = next opposing HTF swing
input double FallbackRR         = 3.0;      // RR multiple if HTF TP unavailable

input group "=== Trade management ==="
input bool   UseBreakEven       = true;
input double BERTriggerR        = 1.0;      // move to BE at +N R
input double BELockPoints       = 5;        // lock N points beyond entry
input bool   UseATRTrail        = true;
input int    ATRPeriod          = 14;
input double ATRTrailMultiplier = 1.5;
input bool   PartialAtR         = true;     // close half at 1R
input double PartialPercent     = 50.0;     // % closed at PartialAtR

input group "=== Risk ==="
input double RiskPercent        = 1.0;
input double DailyDrawdownPct   = 3.0;
input int    MaxConcurrentTrades= 1;
input ulong  MagicNumber        = 902501;
input int    SlippagePoints     = 30;

input group "=== Symbol behaviour ==="
input bool   AutoSymbolPreset   = true;     // pick spread cap + SL by symbol
input double MaxSpreadPointsIn  = 30;       // used when AutoSymbolPreset = false
input double MinSLPointsIn      = 50;       // used when AutoSymbolPreset = false
input double ATRSLMultiplier    = 1.2;      // SL >= ATR*k for chop protection

input group "=== Session filter (server time) ==="
input bool   FilterBySession    = true;
input int    LondonOpenHour     = 7;
input int    NYCloseHour        = 21;

input group "=== Self-learning ==="
input bool   UseLearning        = true;
input int    MinSamplesPerSetup = 12;       // wait this many trades before judging
input double MinSetupWinRate    = 0.40;     // suppress bucket below this WR
input int    LearningWindow     = 50;       // rolling sample window per bucket
input bool   PersistJournal     = true;

input group "=== Alerts ==="
input bool   AlertPopup         = true;
input bool   AlertPush          = false;
input bool   AlertEmail         = false;

//============================== TYPES ============================
struct Swing
{
   datetime t;
   double   price;
   bool     isHigh;
   int      shift;
};

struct Zone
{
   datetime t;
   double   top;
   double   bot;
   bool     bullish;
   bool     dead;
   int      shift;
};

enum TrendDir { TREND_NONE = 0, TREND_UP = 1, TREND_DOWN = -1 };

struct OpenContext
{
   ulong    ticket;
   bool     bullish;
   double   entry;
   double   slInit;
   double   tpInit;
   double   riskDist;
   bool     htfAgree;
   bool     hadFVG;
   bool     hadSweep;
   int      session;
   bool     atBE;
   bool     partialDone;
   datetime opened;
};

struct JournalRow
{
   datetime closeTime;
   bool     bullish;
   bool     htfAgree;
   bool     hadFVG;
   bool     hadSweep;
   int      session;
   double   rMultiple;
   bool     win;
};

//============================== STATE ============================
CTrade        gTrade;
CPositionInfo gPos;
CSymbolInfo   gSym;
CDealInfo     gDeal;

#define SWING_CAP   512
#define ZONE_CAP    128
#define HTF_CAP     128
#define OPENCTX_CAP 16
#define JOURNAL_CAP 1024
#define BUCKET_CAP  64

// LTF structure
Swing g_sw [SWING_CAP];   int g_swN  = 0;
Zone  g_ob [ZONE_CAP];    int g_obN  = 0;
Zone  g_fvg[ZONE_CAP];    int g_fvgN = 0;

// HTF structure
Swing g_swH [HTF_CAP];    int g_swHN = 0;
Zone  g_obH [HTF_CAP];    int g_obHN = 0;

TrendDir g_trend     = TREND_NONE;
TrendDir g_prevTrend = TREND_NONE;
TrendDir g_htfTrend  = TREND_NONE;

datetime g_lastBarTime    = 0;
datetime g_lastHTFBarTime = 0;
datetime g_dayStamp       = 0;
double   g_dayStartEquity = 0.0;
bool     g_haltedToday    = false;

// Per-symbol effective settings
double g_maxSpreadPts = 30;
double g_minSLPts     = 50;

// ATR handles (chart TF)
int    g_atrHandle = INVALID_HANDLE;

// Open-trade context map (small array)
OpenContext g_openCtx[OPENCTX_CAP];
int         g_openCtxN = 0;

// Self-learning journal
JournalRow g_journal[JOURNAL_CAP];
int        g_journalN = 0;

const string OBJP = "MS_";

//============================== INIT =============================
int OnInit()
{
   if(!gSym.Name(_Symbol))
      return INIT_FAILED;

   gTrade.SetExpertMagicNumber(MagicNumber);
   gTrade.SetMarginMode();
   gTrade.SetTypeFillingBySymbol(_Symbol);
   gTrade.SetDeviationInPoints(SlippagePoints);

   ApplySymbolPreset();

   g_atrHandle = iATR(_Symbol, _Period, ATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      Print("Warning: ATR handle failed; trailing/SL fallback only.");

   ResetDailyTracking();
   if(ShowChartMarkup) ObjectsDeleteAll(0, OBJP);

   if(UseLearning && PersistJournal) LoadJournal();

   Print(StringFormat("PhotonMS init: %s spreadCap=%.0fp minSL=%.0fp",
                      _Symbol, g_maxSpreadPts, g_minSLPts));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ShowChartMarkup)
   {
      ObjectsDeleteAll(0, OBJP);
      ChartRedraw(0);
   }
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(UseLearning && PersistJournal) SaveJournal();
}

//============================== SYMBOL PRESETS ===================
void ApplySymbolPreset()
{
   if(!AutoSymbolPreset)
   {
      g_maxSpreadPts = MaxSpreadPointsIn;
      g_minSLPts     = MinSLPointsIn;
      return;
   }

   string s = _Symbol;
   StringToUpper(s);

   if(StringFind(s, "US30")  >= 0 || StringFind(s, "DJ")   >= 0
   || StringFind(s, "WS30")  >= 0 || StringFind(s, "DOW")  >= 0)
   {
      g_maxSpreadPts = 80;
      g_minSLPts     = 300;
   }
   else if(StringFind(s, "US100") >= 0 || StringFind(s, "NAS100") >= 0
        || StringFind(s, "NDX")   >= 0 || StringFind(s, "NASDAQ") >= 0)
   {
      g_maxSpreadPts = 80;
      g_minSLPts     = 300;
   }
   else if(StringFind(s, "US500") >= 0 || StringFind(s, "SPX500") >= 0
        || StringFind(s, "SP500") >= 0 || StringFind(s, "SPX")    >= 0)
   {
      g_maxSpreadPts = 50;
      g_minSLPts     = 100;
   }
   else if(StringFind(s, "XAU")  >= 0 || StringFind(s, "GOLD") >= 0)
   {
      g_maxSpreadPts = 60;
      g_minSLPts     = 200;
   }
   else
   {
      g_maxSpreadPts = MaxSpreadPointsIn;
      g_minSLPts     = MinSLPointsIn;
   }
}

//============================== ALERTS ===========================
void FireAlert(const string msg)
{
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("PhotonMS", msg);
   Print(msg);
}

//============================== DAILY DD =========================
void ResetDailyTracking()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(g_dayStamp != today)
   {
      g_dayStamp        = today;
      g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      g_haltedToday     = false;
   }
}

bool DailyHalted()
{
   if(DailyDrawdownPct <= 0.0 || g_dayStartEquity <= 0.0) return false;
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (g_dayStartEquity - eq) / g_dayStartEquity * 100.0;
   if(ddPct >= DailyDrawdownPct)
   {
      if(!g_haltedToday)
      {
         FireAlert(StringFormat("%s daily DD %.2f%% — halting today.",
                                _Symbol, ddPct));
         g_haltedToday = true;
      }
      return true;
   }
   return false;
}

//============================== SESSION ==========================
int CurrentSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(h >= 0  && h <  7)  return 0;  // Asia
   if(h >= 7  && h < 13)  return 1;  // London
   return 2;                          // NY / overlap
}

bool InTradingSession()
{
   if(!FilterBySession) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= LondonOpenHour && dt.hour < NYCloseHour);
}

//============================== ON-TICK ==========================
void OnTick()
{
   ResetDailyTracking();

   // 1. HTF refresh only when HTF bar changes
   if(UseHTFBias)
   {
      datetime htfBar = iTime(_Symbol, HTFPeriod, 0);
      if(htfBar != g_lastHTFBarTime)
      {
         g_lastHTFBarTime = htfBar;
         RefreshHTF();
      }
   }

   // 2. LTF refresh only when LTF bar changes
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_lastBarTime)
   {
      g_lastBarTime = curBar;
      RefreshStructure();
      if(ShowChartMarkup) RedrawMarkup();
   }

   // 3. Per-tick: manage open positions then look for entries
   ManageOpenPositions();
   if(EntryOnOBRetrace && InTradingSession())
      TryEnter();
}

//============================== HTF ANALYSIS =====================
void RefreshHTF()
{
   int n = MathMin(HTFAnalysisBars, Bars(_Symbol, HTFPeriod));
   if(n < HTFSwingLength * 2 + 5) return;

   MqlRates r[]; ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, HTFPeriod, 0, n, r);
   if(copied <= 0) return;
   n = copied;

   g_swHN = 0;
   g_obHN = 0;

   // HTF swings
   for(int i = n - HTFSwingLength - 1; i >= HTFSwingLength; i--)
   {
      double hi = r[i].high, lo = r[i].low;
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= HTFSwingLength && (isHigh || isLow); j++)
      {
         if(isHigh && (hi <= r[i-j].high || hi <= r[i+j].high)) isHigh = false;
         if(isLow  && (lo >= r[i-j].low  || lo >= r[i+j].low )) isLow  = false;
      }
      if(isHigh && g_swHN < HTF_CAP)
      {
         g_swH[g_swHN].t = r[i].time; g_swH[g_swHN].price = hi;
         g_swH[g_swHN].isHigh = true; g_swH[g_swHN].shift = i;
         g_swHN++;
      }
      if(isLow && g_swHN < HTF_CAP)
      {
         g_swH[g_swHN].t = r[i].time; g_swH[g_swHN].price = lo;
         g_swH[g_swHN].isHigh = false; g_swH[g_swHN].shift = i;
         g_swHN++;
      }
   }
   if(g_swHN < 4) { g_htfTrend = TREND_NONE; return; }

   // HTF trend
   double lastHi=0, prevHi=0, lastLo=0, prevLo=0;
   for(int i = g_swHN - 1; i >= 0; i--)
   {
      if(g_swH[i].isHigh)
      {
         if(lastHi == 0)      lastHi = g_swH[i].price;
         else if(prevHi == 0) prevHi = g_swH[i].price;
      }
      else
      {
         if(lastLo == 0)      lastLo = g_swH[i].price;
         else if(prevLo == 0) prevLo = g_swH[i].price;
      }
      if(lastHi && prevHi && lastLo && prevLo) break;
   }
   TrendDir prev = g_htfTrend;
   if(lastHi > prevHi && lastLo > prevLo)      g_htfTrend = TREND_UP;
   else if(lastHi < prevHi && lastLo < prevLo) g_htfTrend = TREND_DOWN;

   if(prev != TREND_NONE && g_htfTrend != TREND_NONE && prev != g_htfTrend)
      FireAlert(StringFormat("%s HTF bias flip: %s",
                             _Symbol,
                             g_htfTrend == TREND_UP ? "BULLISH" : "BEARISH"));

   // HTF order blocks (lighter pass: only the last opposing candle before each BOS)
   double trackedHi = 0, trackedLo = 0;
   for(int s = 0; s < g_swHN; s++)
   {
      if(g_swH[s].isHigh)
      {
         if(trackedHi > 0 && g_swH[s].price > trackedHi)
         {
            int sIdx = g_swH[s].shift;
            for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
               if(r[k].close < r[k].open && g_obHN < HTF_CAP)
               {
                  g_obH[g_obHN].t = r[k].time;
                  g_obH[g_obHN].top = MathMax(r[k].open, r[k].close);
                  g_obH[g_obHN].bot = r[k].low;
                  g_obH[g_obHN].bullish = true;
                  g_obH[g_obHN].dead = false;
                  g_obH[g_obHN].shift = k;
                  g_obHN++;
                  break;
               }
         }
         trackedHi = g_swH[s].price;
      }
      else
      {
         if(trackedLo > 0 && g_swH[s].price < trackedLo)
         {
            int sIdx = g_swH[s].shift;
            for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
               if(r[k].close > r[k].open && g_obHN < HTF_CAP)
               {
                  g_obH[g_obHN].t = r[k].time;
                  g_obH[g_obHN].top = r[k].high;
                  g_obH[g_obHN].bot = MathMin(r[k].open, r[k].close);
                  g_obH[g_obHN].bullish = false;
                  g_obH[g_obHN].dead = false;
                  g_obH[g_obHN].shift = k;
                  g_obHN++;
                  break;
               }
         }
         trackedLo = g_swH[s].price;
      }
   }
   MarkZoneMitigation(g_obH, g_obHN, r, n);
}

//============================== LTF ANALYSIS =====================
void RefreshStructure()
{
   int n = MathMin(AnalysisBars, Bars(_Symbol, _Period));
   if(n < SwingLength * 2 + 5) return;

   MqlRates r[]; ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, _Period, 0, n, r);
   if(copied <= 0) return;
   n = copied;

   g_swN  = 0;
   g_obN  = 0;
   g_fvgN = 0;

   // swings
   for(int i = n - SwingLength - 1; i >= SwingLength; i--)
   {
      double hi = r[i].high, lo = r[i].low;
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= SwingLength && (isHigh || isLow); j++)
      {
         if(isHigh && (hi <= r[i-j].high || hi <= r[i+j].high)) isHigh = false;
         if(isLow  && (lo >= r[i-j].low  || lo >= r[i+j].low )) isLow  = false;
      }
      if(isHigh && g_swN < SWING_CAP)
      {
         g_sw[g_swN].t = r[i].time; g_sw[g_swN].price = hi;
         g_sw[g_swN].isHigh = true; g_sw[g_swN].shift = i; g_swN++;
      }
      if(isLow && g_swN < SWING_CAP)
      {
         g_sw[g_swN].t = r[i].time; g_sw[g_swN].price = lo;
         g_sw[g_swN].isHigh = false; g_sw[g_swN].shift = i; g_swN++;
      }
   }
   if(g_swN < 4) return;

   // trend
   double lastHi=0, prevHi=0, lastLo=0, prevLo=0;
   for(int i = g_swN - 1; i >= 0; i--)
   {
      if(g_sw[i].isHigh)
      {
         if(lastHi == 0)      lastHi = g_sw[i].price;
         else if(prevHi == 0) prevHi = g_sw[i].price;
      }
      else
      {
         if(lastLo == 0)      lastLo = g_sw[i].price;
         else if(prevLo == 0) prevLo = g_sw[i].price;
      }
      if(lastHi && prevHi && lastLo && prevLo) break;
   }
   g_prevTrend = g_trend;
   if(lastHi > prevHi && lastLo > prevLo)      g_trend = TREND_UP;
   else if(lastHi < prevHi && lastLo < prevLo) g_trend = TREND_DOWN;

   if(UseCHoCH && g_prevTrend != TREND_NONE && g_trend != TREND_NONE
      && g_trend != g_prevTrend)
      FireAlert(StringFormat("%s %s CHoCH",
                             _Symbol,
                             g_trend == TREND_UP ? "BULLISH" : "BEARISH"));

   // order blocks
   if(UseOrderBlocks)
   {
      double trackedHi=0, trackedLo=0;
      for(int s = 0; s < g_swN; s++)
      {
         if(g_sw[s].isHigh)
         {
            if(trackedHi > 0 && g_sw[s].price > trackedHi)
            {
               int sIdx = g_sw[s].shift;
               for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
                  if(r[k].close < r[k].open && g_obN < ZONE_CAP)
                  {
                     g_ob[g_obN].t = r[k].time;
                     g_ob[g_obN].top = MathMax(r[k].open, r[k].close);
                     g_ob[g_obN].bot = r[k].low;
                     g_ob[g_obN].bullish = true;
                     g_ob[g_obN].dead = false;
                     g_ob[g_obN].shift = k;
                     g_obN++;
                     break;
                  }
            }
            trackedHi = g_sw[s].price;
         }
         else
         {
            if(trackedLo > 0 && g_sw[s].price < trackedLo)
            {
               int sIdx = g_sw[s].shift;
               for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
                  if(r[k].close > r[k].open && g_obN < ZONE_CAP)
                  {
                     g_ob[g_obN].t = r[k].time;
                     g_ob[g_obN].top = r[k].high;
                     g_ob[g_obN].bot = MathMin(r[k].open, r[k].close);
                     g_ob[g_obN].bullish = false;
                     g_ob[g_obN].dead = false;
                     g_ob[g_obN].shift = k;
                     g_obN++;
                     break;
                  }
            }
            trackedLo = g_sw[s].price;
         }
      }
   }

   // FVGs
   if(UseFVG)
   {
      for(int i = 2; i < n - 1 && g_fvgN < ZONE_CAP; i++)
      {
         if(r[i+2].high < r[i].low)
         {
            g_fvg[g_fvgN].t = r[i+1].time;
            g_fvg[g_fvgN].top = r[i].low;
            g_fvg[g_fvgN].bot = r[i+2].high;
            g_fvg[g_fvgN].bullish = true;
            g_fvg[g_fvgN].dead = false;
            g_fvg[g_fvgN].shift = i+1;
            g_fvgN++;
         }
         else if(r[i+2].low > r[i].high)
         {
            g_fvg[g_fvgN].t = r[i+1].time;
            g_fvg[g_fvgN].top = r[i+2].low;
            g_fvg[g_fvgN].bot = r[i].high;
            g_fvg[g_fvgN].bullish = false;
            g_fvg[g_fvgN].dead = false;
            g_fvg[g_fvgN].shift = i+1;
            g_fvgN++;
         }
      }
   }

   MarkZoneMitigation(g_ob,  g_obN,  r, n);
   MarkZoneMitigation(g_fvg, g_fvgN, r, n);

   for(int i = 0; i < g_obN;  i++) if(g_ob[i].shift  > MaxZoneAgeBars) g_ob[i].dead  = true;
   for(int i = 0; i < g_fvgN; i++) if(g_fvg[i].shift > MaxZoneAgeBars) g_fvg[i].dead = true;

   // sweep alert
   if(UseLiquiditySweep && n >= 3)
   {
      double h1 = r[1].high, l1 = r[1].low, c1 = r[1].close;
      double recentHi = 0, recentLo = 0;
      for(int s = g_swN - 1; s >= 0 && (recentHi == 0 || recentLo == 0); s--)
      {
         if(g_sw[s].t >= r[1].time) continue;
         if(g_sw[s].isHigh && recentHi == 0) recentHi = g_sw[s].price;
         if(!g_sw[s].isHigh && recentLo == 0) recentLo = g_sw[s].price;
      }
      if(recentHi > 0 && h1 > recentHi && c1 < recentHi)
         FireAlert(StringFormat("%s SELL sweep above %s",
                                _Symbol, DoubleToString(recentHi, _Digits)));
      if(recentLo > 0 && l1 < recentLo && c1 > recentLo)
         FireAlert(StringFormat("%s BUY sweep below %s",
                                _Symbol, DoubleToString(recentLo, _Digits)));
   }
}

void MarkZoneMitigation(Zone &arr[], int count, const MqlRates &r[], int n)
{
   for(int z = 0; z < count; z++)
   {
      int zIdx = arr[z].shift;
      if(zIdx <= 0 || zIdx >= n) continue;
      for(int k = zIdx - 1; k >= 0; k--)
      {
         if(arr[z].bullish && r[k].low  <= arr[z].top) { arr[z].dead = true; break; }
         if(!arr[z].bullish && r[k].high >= arr[z].bot){ arr[z].dead = true; break; }
      }
   }
}

//============================== ENTRY HELPERS ====================
bool HasFVGInside(const Zone &ob)
{
   for(int z = 0; z < g_fvgN; z++)
   {
      if(g_fvg[z].dead) continue;
      if(g_fvg[z].bullish != ob.bullish) continue;
      if(g_fvg[z].top >= ob.bot && g_fvg[z].bot <= ob.top) return true;
   }
   return false;
}

bool InHTFZone(const Zone &ob)
{
   for(int z = 0; z < g_obHN; z++)
   {
      if(g_obH[z].dead) continue;
      if(g_obH[z].bullish != ob.bullish) continue;
      if(g_obH[z].top >= ob.bot && g_obH[z].bot <= ob.top) return true;
   }
   return false;
}

bool HadRecentSweep(bool bullish)
{
   // sweep alerts only fire on bar close — approximate by checking last
   // 5 bars for a wick beyond a prior swing then close back inside.
   MqlRates r[]; ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 0, 10, r) < 10) return false;
   for(int i = 1; i <= 5; i++)
   {
      // find prior swing
      double sw = 0;
      for(int s = g_swN - 1; s >= 0; s--)
      {
         if(g_sw[s].t >= r[i].time) continue;
         if(bullish && !g_sw[s].isHigh) { sw = g_sw[s].price; break; }
         if(!bullish && g_sw[s].isHigh) { sw = g_sw[s].price; break; }
      }
      if(sw == 0) continue;
      if(bullish && r[i].low < sw && r[i].close > sw)  return true;
      if(!bullish && r[i].high > sw && r[i].close < sw) return true;
   }
   return false;
}

double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0;
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, buf) <= 0) return 0;
   return buf[0];
}

// Next opposing HTF swing (for TP). For longs: nearest swing high above
// current price; for shorts: nearest swing low below.
double NextHTFTarget(bool bullish, double fromPrice)
{
   double best = 0;
   for(int s = 0; s < g_swHN; s++)
   {
      if(bullish && g_swH[s].isHigh && g_swH[s].price > fromPrice)
      {
         if(best == 0 || g_swH[s].price < best) best = g_swH[s].price;
      }
      if(!bullish && !g_swH[s].isHigh && g_swH[s].price < fromPrice)
      {
         if(best == 0 || g_swH[s].price > best) best = g_swH[s].price;
      }
   }
   return best;
}

//============================== ENTRY ============================
void TryEnter()
{
   if(g_haltedToday || DailyHalted()) return;
   if(CountMyOpenTrades() >= MaxConcurrentTrades) return;
   if(!gSym.RefreshRates()) return;

   double spread = (gSym.Ask() - gSym.Bid()) / _Point;
   if(g_maxSpreadPts > 0 && spread > g_maxSpreadPts) return;

   double bid = gSym.Bid();
   double ask = gSym.Ask();

   for(int z = 0; z < g_obN; z++)
   {
      if(g_ob[z].dead) continue;

      bool bullish = g_ob[z].bullish;

      // HTF agreement
      bool htfAgree = (g_htfTrend == TREND_NONE)
                    || (bullish && g_htfTrend == TREND_UP)
                    || (!bullish && g_htfTrend == TREND_DOWN);
      if(UseHTFBias && RequireHTFAgree && !htfAgree) continue;

      // local trend agreement (kept softer than HTF)
      if(bullish && g_trend == TREND_DOWN) continue;
      if(!bullish && g_trend == TREND_UP)  continue;

      // FVG / sweep filters
      bool hadFVG = HasFVGInside(g_ob[z]);
      if(RequireFVGInOB && !hadFVG) continue;
      bool hadSweep = HadRecentSweep(bullish);
      if(RequireSweep && !hadSweep) continue;

      // Soft preference: zones overlapping HTF zones get priority
      // (skip non-HTF zones if a tap occurred and PreferHTFZones is on)
      bool inHTFZone = InHTFZone(g_ob[z]);
      if(PreferHTFZones && UseHTFBias && !inHTFZone && g_obHN > 0) continue;

      // Tap check
      bool tap = bullish
                 ? (bid <= g_ob[z].top && bid >= g_ob[z].bot)
                 : (ask >= g_ob[z].bot && ask <= g_ob[z].top);
      if(!tap) continue;

      // Self-learning filter
      int session = CurrentSession();
      if(UseLearning && !SetupAllowed(htfAgree, hadFVG, hadSweep, session))
      {
         Print(StringFormat("%s setup suppressed by learning (HTFa=%d FVG=%d SW=%d sess=%d)",
                            _Symbol, htfAgree, hadFVG, hadSweep, session));
         continue;
      }

      OpenTrade(bullish, g_ob[z], htfAgree, hadFVG, hadSweep, session);
      g_ob[z].dead = true;
      return;
   }
}

//============================== OPEN TRADE =======================
void OpenTrade(bool buy, const Zone &ob,
               bool htfAgree, bool hadFVG, bool hadSweep, int session)
{
   double atr     = GetATR();
   double minSL   = g_minSLPts * _Point;
   double atrSL   = atr * ATRSLMultiplier;
   double basePad = MathMax(minSL, atrSL);

   double entry, sl, tp, riskDist;

   if(buy)
   {
      entry    = gSym.Ask();
      sl       = MathMin(ob.bot - basePad, entry - basePad);
      riskDist = entry - sl;
      if(riskDist <= 0) return;

      if(TPFromHTFSwing)
      {
         double t = NextHTFTarget(true, entry);
         tp = (t > 0) ? t : entry + FallbackRR * riskDist;
      }
      else tp = entry + FallbackRR * riskDist;
   }
   else
   {
      entry    = gSym.Bid();
      sl       = MathMax(ob.top + basePad, entry + basePad);
      riskDist = sl - entry;
      if(riskDist <= 0) return;

      if(TPFromHTFSwing)
      {
         double t = NextHTFTarget(false, entry);
         tp = (t > 0) ? t : entry - FallbackRR * riskDist;
      }
      else tp = entry - FallbackRR * riskDist;
   }

   double rr = MathAbs(tp - entry) / riskDist;
   if(rr < MinRewardToRisk) return;

   double lots = CalcLots(riskDist);
   if(lots <= 0) return;

   string tag  = buy ? "BUY" : "SELL";
   string msg  = StringFormat("%s %s %s @%s SL=%s TP=%s RR=%.1f lots=%.2f [HTFa=%d FVG=%d SW=%d]",
                              AlertsOnly ? "[SIM]" : "[LIVE]",
                              _Symbol, tag,
                              DoubleToString(entry, _Digits),
                              DoubleToString(sl, _Digits),
                              DoubleToString(tp, _Digits),
                              rr, lots, htfAgree, hadFVG, hadSweep);
   FireAlert(msg);

   if(AlertsOnly)
   {
      RegisterOpenContext(0, buy, entry, sl, tp, riskDist,
                          htfAgree, hadFVG, hadSweep, session);
      return;
   }

   bool ok = buy
      ? gTrade.Buy (lots, _Symbol, entry, sl, tp, "MS")
      : gTrade.Sell(lots, _Symbol, entry, sl, tp, "MS");
   if(!ok)
   {
      Print("Order failed: ", gTrade.ResultRetcodeDescription());
      return;
   }
   ulong ticket = gTrade.ResultDeal();
   if(ticket == 0) ticket = gTrade.ResultOrder();
   RegisterOpenContext(ticket, buy, entry, sl, tp, riskDist,
                       htfAgree, hadFVG, hadSweep, session);
}

double CalcLots(double slDistancePrice)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistancePrice <= 0) return 0;
   double lossPerLot = slDistancePrice / tickSize * tickValue;
   if(lossPerLot <= 0) return 0;
   double lots = riskMoney / lossPerLot;
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));
   return lots;
}

int CountMyOpenTrades()
{
   int total = PositionsTotal(), c = 0;
   for(int i = 0; i < total; i++)
      if(gPos.SelectByIndex(i) && gPos.Magic() == MagicNumber
         && gPos.Symbol() == _Symbol) c++;
   return c;
}

//============================== POSITION MGMT ====================
void ManageOpenPositions()
{
   if(AlertsOnly) return;
   if(!UseBreakEven && !UseATRTrail && !PartialAtR) return;

   double atr = GetATR();

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(!gPos.SelectByIndex(i)) continue;
      if(gPos.Magic() != MagicNumber || gPos.Symbol() != _Symbol) continue;

      ulong ticket = gPos.Ticket();
      OpenContext *ctx = FindContext(ticket);
      if(ctx == NULL) continue;

      double cur     = ctx.bullish ? gSym.Bid() : gSym.Ask();
      if(!gSym.RefreshRates()) continue;
      cur            = ctx.bullish ? gSym.Bid() : gSym.Ask();
      double moved   = ctx.bullish ? (cur - ctx.entry) : (ctx.entry - cur);
      double rNow    = (ctx.riskDist > 0) ? moved / ctx.riskDist : 0.0;

      // partial at 1R
      if(PartialAtR && !ctx.partialDone && rNow >= 1.0)
      {
         double curVol = gPos.Volume();
         double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double partV  = curVol * PartialPercent / 100.0;
         partV = MathFloor(partV / step) * step;
         if(partV >= minVol && (curVol - partV) >= minVol)
         {
            if(gTrade.PositionClosePartial(ticket, partV))
               ctx.partialDone = true;
         }
      }

      // break-even
      if(UseBreakEven && !ctx.atBE && rNow >= BERTriggerR)
      {
         double newSL = ctx.bullish
                        ? ctx.entry + BELockPoints * _Point
                        : ctx.entry - BELockPoints * _Point;
         if((ctx.bullish && newSL > gPos.StopLoss())
            || (!ctx.bullish && (gPos.StopLoss() == 0 || newSL < gPos.StopLoss())))
         {
            if(gTrade.PositionModify(ticket, newSL, gPos.TakeProfit()))
               ctx.atBE = true;
         }
      }

      // ATR trail (only after BE)
      if(UseATRTrail && ctx.atBE && atr > 0)
      {
         double trail = ctx.bullish
                        ? cur - atr * ATRTrailMultiplier
                        : cur + atr * ATRTrailMultiplier;
         if(ctx.bullish)
         {
            if(trail > gPos.StopLoss() && trail < cur)
               gTrade.PositionModify(ticket, trail, gPos.TakeProfit());
         }
         else
         {
            double curSL = gPos.StopLoss();
            if((curSL == 0 || trail < curSL) && trail > cur)
               gTrade.PositionModify(ticket, trail, gPos.TakeProfit());
         }
      }
   }
}

//============================== OPEN CTX MAP =====================
void RegisterOpenContext(ulong ticket, bool buy, double entry, double sl,
                         double tp, double riskDist,
                         bool htfAgree, bool hadFVG, bool hadSweep, int session)
{
   if(g_openCtxN >= OPENCTX_CAP)
   {
      for(int i = 0; i < OPENCTX_CAP - 1; i++) g_openCtx[i] = g_openCtx[i + 1];
      g_openCtxN = OPENCTX_CAP - 1;
   }
   g_openCtx[g_openCtxN].ticket      = ticket;
   g_openCtx[g_openCtxN].bullish     = buy;
   g_openCtx[g_openCtxN].entry       = entry;
   g_openCtx[g_openCtxN].slInit      = sl;
   g_openCtx[g_openCtxN].tpInit      = tp;
   g_openCtx[g_openCtxN].riskDist    = riskDist;
   g_openCtx[g_openCtxN].htfAgree    = htfAgree;
   g_openCtx[g_openCtxN].hadFVG      = hadFVG;
   g_openCtx[g_openCtxN].hadSweep    = hadSweep;
   g_openCtx[g_openCtxN].session     = session;
   g_openCtx[g_openCtxN].atBE        = false;
   g_openCtx[g_openCtxN].partialDone = false;
   g_openCtx[g_openCtxN].opened      = TimeCurrent();
   g_openCtxN++;
}

OpenContext* FindContext(ulong ticket)
{
   for(int i = 0; i < g_openCtxN; i++)
      if(g_openCtx[i].ticket == ticket) return GetPointer(g_openCtx[i]);
   return NULL;
}

void RemoveContext(ulong ticket)
{
   for(int i = 0; i < g_openCtxN; i++)
   {
      if(g_openCtx[i].ticket == ticket)
      {
         for(int j = i; j < g_openCtxN - 1; j++) g_openCtx[j] = g_openCtx[j + 1];
         g_openCtxN--;
         return;
      }
   }
}

//============================== TRADE EVENTS =====================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!gDeal.SelectByIndex(0)) {}        // no-op (CDealInfo uses ticket)
   if(!gDeal.Ticket()) {}

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket)) return;
   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic != (long)MagicNumber) return;
   string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(sym != _Symbol) return;

   long entryFlag = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entryFlag != DEAL_ENTRY_OUT && entryFlag != DEAL_ENTRY_OUT_BY) return;

   ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   OpenContext *ctx = FindContext(posId);
   // also try matching by ticket (in case we stored order ticket)
   if(ctx == NULL) ctx = FindContext(dealTicket);
   if(ctx == NULL) return;

   double closePx = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double moved   = ctx.bullish ? (closePx - ctx.entry) : (ctx.entry - closePx);
   double r       = (ctx.riskDist > 0) ? moved / ctx.riskDist : 0.0;

   AddJournal(ctx.bullish, ctx.htfAgree, ctx.hadFVG, ctx.hadSweep,
              ctx.session, r, r > 0.0);
   RemoveContext(posId);
}

//============================== SELF-LEARNING ====================
int BucketIndex(bool htfAgree, bool hadFVG, bool hadSweep, int session)
{
   int b = 0;
   b |= (htfAgree ? 1 : 0) << 0;
   b |= (hadFVG   ? 1 : 0) << 1;
   b |= (hadSweep ? 1 : 0) << 2;
   b |= (session & 0x3) << 3;
   return b;            // 0..31
}

bool SetupAllowed(bool htfAgree, bool hadFVG, bool hadSweep, int session)
{
   int target = BucketIndex(htfAgree, hadFVG, hadSweep, session);
   int wins = 0, total = 0;
   int seen = 0;
   for(int i = g_journalN - 1; i >= 0 && seen < LearningWindow; i--)
   {
      int b = BucketIndex(g_journal[i].htfAgree, g_journal[i].hadFVG,
                          g_journal[i].hadSweep, g_journal[i].session);
      if(b != target) continue;
      total++;
      if(g_journal[i].win) wins++;
      seen++;
   }
   if(total < MinSamplesPerSetup) return true;   // not enough data yet
   double wr = (double)wins / (double)total;
   return wr >= MinSetupWinRate;
}

void AddJournal(bool bullish, bool htfAgree, bool hadFVG, bool hadSweep,
                int session, double rMult, bool win)
{
   if(g_journalN >= JOURNAL_CAP)
   {
      for(int i = 0; i < JOURNAL_CAP - 1; i++) g_journal[i] = g_journal[i + 1];
      g_journalN = JOURNAL_CAP - 1;
   }
   g_journal[g_journalN].closeTime = TimeCurrent();
   g_journal[g_journalN].bullish   = bullish;
   g_journal[g_journalN].htfAgree  = htfAgree;
   g_journal[g_journalN].hadFVG    = hadFVG;
   g_journal[g_journalN].hadSweep  = hadSweep;
   g_journal[g_journalN].session   = session;
   g_journal[g_journalN].rMultiple = rMult;
   g_journal[g_journalN].win       = win;
   g_journalN++;

   FireAlert(StringFormat("%s trade closed: %s R=%.2f (HTFa=%d FVG=%d SW=%d sess=%d)",
                          _Symbol, win ? "WIN" : "LOSS",
                          rMult, htfAgree, hadFVG, hadSweep, session));

   if(PersistJournal) SaveJournal();
}

string JournalFileName()
{
   string s = _Symbol;
   StringReplace(s, ".", "_");
   StringReplace(s, "#", "_");
   return StringFormat("PhotonMS_journal_%s.csv", s);
}

void LoadJournal()
{
   g_journalN = 0;
   string fn = JournalFileName();
   int h = FileOpen(fn, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) return;
   FileReadString(h);  // header
   FileReadString(h); FileReadString(h); FileReadString(h);
   FileReadString(h); FileReadString(h); FileReadString(h); FileReadString(h);
   while(!FileIsEnding(h) && g_journalN < JOURNAL_CAP)
   {
      string cTime = FileReadString(h);
      if(cTime == "") break;
      string sBul  = FileReadString(h);
      string sHTF  = FileReadString(h);
      string sFVG  = FileReadString(h);
      string sSW   = FileReadString(h);
      string sSess = FileReadString(h);
      string sR    = FileReadString(h);
      string sWin  = FileReadString(h);
      g_journal[g_journalN].closeTime = StringToTime(cTime);
      g_journal[g_journalN].bullish   = (StringToInteger(sBul) != 0);
      g_journal[g_journalN].htfAgree  = (StringToInteger(sHTF) != 0);
      g_journal[g_journalN].hadFVG    = (StringToInteger(sFVG) != 0);
      g_journal[g_journalN].hadSweep  = (StringToInteger(sSW)  != 0);
      g_journal[g_journalN].session   = (int)StringToInteger(sSess);
      g_journal[g_journalN].rMultiple = StringToDouble(sR);
      g_journal[g_journalN].win       = (StringToInteger(sWin) != 0);
      g_journalN++;
   }
   FileClose(h);
   Print(StringFormat("Loaded %d journal rows for %s", g_journalN, _Symbol));
}

void SaveJournal()
{
   string fn = JournalFileName();
   int h = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "closeTime", "bullish", "htfAgree", "hadFVG",
                "hadSweep", "session", "rMultiple", "win");
   for(int i = 0; i < g_journalN; i++)
      FileWrite(h,
         TimeToString(g_journal[i].closeTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
         g_journal[i].bullish  ? 1 : 0,
         g_journal[i].htfAgree ? 1 : 0,
         g_journal[i].hadFVG   ? 1 : 0,
         g_journal[i].hadSweep ? 1 : 0,
         g_journal[i].session,
         DoubleToString(g_journal[i].rMultiple, 3),
         g_journal[i].win ? 1 : 0);
   FileClose(h);
}

//============================== MARKUP ===========================
void RedrawMarkup()
{
   ObjectsDeleteAll(0, OBJP);
   datetime tEnd = iTime(_Symbol, _Period, 0) + PeriodSeconds() * 20;

   for(int s = 0; s < g_swN; s++)
   {
      string nm = OBJP + (g_sw[s].isHigh ? "H_" : "L_") + IntegerToString(s);
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_sw[s].t, g_sw[s].price);
      ObjectSetString (0, nm, OBJPROP_TEXT,       g_sw[s].isHigh ? "H" : "L");
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      g_sw[s].isHigh ? clrLimeGreen : clrRed);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     g_sw[s].isHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
   }
   for(int z = 0; z < g_obN; z++)
   {
      if(g_ob[z].dead) continue;
      string nm = OBJP + "OB_" + IntegerToString(z);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_ob[z].t, g_ob[z].top, tEnd, g_ob[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_ob[z].bullish ? clrTeal : clrFireBrick);
      ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
      ObjectSetInteger(0, nm, OBJPROP_FILL,  true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   for(int z = 0; z < g_obHN; z++)
   {
      if(g_obH[z].dead) continue;
      string nm = OBJP + "HOB_" + IntegerToString(z);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_obH[z].t, g_obH[z].top, tEnd, g_obH[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_obH[z].bullish ? clrDodgerBlue : clrMagenta);
      ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   for(int z = 0; z < g_fvgN; z++)
   {
      if(g_fvg[z].dead) continue;
      string nm = OBJP + "FVG_" + IntegerToString(z);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_fvg[z].t, g_fvg[z].top, tEnd, g_fvg[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_fvg[z].bullish ? clrDarkGreen : clrDarkRed);
      ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
      ObjectSetInteger(0, nm, OBJPROP_FILL,  true);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }

   string tn = OBJP + "TREND";
   ObjectCreate(0, tn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tn, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, tn, OBJPROP_YDISTANCE, 20);
   color tc = g_trend == TREND_UP ? clrLimeGreen :
              g_trend == TREND_DOWN ? clrRed : clrGray;
   string trendTxt = StringFormat("LTF: %s   HTF: %s   journal: %d",
                                  g_trend == TREND_UP   ? "UP" :
                                  g_trend == TREND_DOWN ? "DN" : "-",
                                  g_htfTrend == TREND_UP   ? "UP" :
                                  g_htfTrend == TREND_DOWN ? "DN" : "-",
                                  g_journalN);
   ObjectSetString (0, tn, OBJPROP_TEXT,  trendTxt);
   ObjectSetInteger(0, tn, OBJPROP_COLOR, tc);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
