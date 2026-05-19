//+------------------------------------------------------------------+
//|                                    PhotonMarketStructureEA.mq5   |
//|  Market-structure trading bot:                                    |
//|    - Swings (HH/HL/LH/LL)                                         |
//|    - BOS & CHoCH (trend continuation vs reversal)                 |
//|    - Order Blocks (last opposing candle before impulse)           |
//|    - Fair Value Gaps (3-bar imbalances)                           |
//|    - Liquidity sweeps (wick + close-back-inside)                  |
//|  Kill switch (AlertsOnly), % equity risk, single-tick fast path.  |
//+------------------------------------------------------------------+
#property copyright "Market Structure Assistant"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//============================== INPUTS ===========================
input group "=== Kill switch ==="
input bool   AlertsOnly         = true;     // true = signal only, no live orders
input bool   ShowChartMarkup    = true;     // draw structure on chart

input group "=== Structure detection ==="
input int    SwingLength        = 5;
input int    AnalysisBars       = 1500;     // bars scanned each refresh
input int    MaxZoneAgeBars     = 250;      // discard OBs/FVGs older than this
input bool   UseCHoCH           = true;
input bool   UseOrderBlocks     = true;
input bool   UseFVG             = true;
input bool   UseLiquiditySweep  = true;

input group "=== Entry rules ==="
input bool   EntryOnOBRetrace   = true;     // enter when price taps an unmitigated OB
input bool   RequireFVGInOB     = false;    // also require an FVG inside the OB
input bool   RequireTrendAgree  = true;     // only trade with current trend
input int    SLPaddingPoints    = 50;
input double RewardToRisk       = 2.0;

input group "=== Risk ==="
input double RiskPercent        = 1.0;      // % equity risk per trade
input double MaxSpreadPoints    = 30;
input double DailyDrawdownPct   = 3.0;      // halt after this much daily DD (0 = off)
input int    MaxConcurrentTrades= 1;
input ulong  MagicNumber        = 902501;
input int    SlippagePoints     = 20;

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
   int      shift;     // index in current series-array snapshot
};

struct Zone
{
   datetime t;
   double   top;
   double   bot;
   bool     bullish;
   bool     dead;      // mitigated/filled
   int      shift;
};

enum TrendDir { TREND_NONE = 0, TREND_UP = 1, TREND_DOWN = -1 };

//============================== STATE ============================
CTrade        gTrade;
CPositionInfo gPos;
CSymbolInfo   gSym;

#define SWING_CAP 512
#define ZONE_CAP  128

Swing  g_sw[SWING_CAP];   int g_swN  = 0;
Zone   g_ob[ZONE_CAP];    int g_obN  = 0;
Zone   g_fvg[ZONE_CAP];   int g_fvgN = 0;

TrendDir g_trend          = TREND_NONE;
TrendDir g_prevTrend      = TREND_NONE;
datetime g_lastBarTime    = 0;
datetime g_dayStamp       = 0;
double   g_dayStartEquity = 0.0;
bool     g_haltedToday    = false;

const string OBJP = "MS_";

//+------------------------------------------------------------------+
int OnInit()
{
   if(!gSym.Name(_Symbol))
      return INIT_FAILED;

   gTrade.SetExpertMagicNumber(MagicNumber);
   gTrade.SetMarginMode();
   gTrade.SetTypeFillingBySymbol(_Symbol);
   gTrade.SetDeviationInPoints(SlippagePoints);

   ResetDailyTracking();
   if(ShowChartMarkup)
      ObjectsDeleteAll(0, OBJP);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ShowChartMarkup)
   {
      ObjectsDeleteAll(0, OBJP);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Per-tick hot path                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyTracking();

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_lastBarTime)
   {
      g_lastBarTime = curBar;
      RefreshStructure();          // heavy work, but only once per bar
      if(ShowChartMarkup)
         RedrawMarkup();
   }

   if(EntryOnOBRetrace)
      TryEnter();                  // tight loop: O(g_obN) zone checks
}

//+------------------------------------------------------------------+
//| Daily DD tracking                                                 |
//+------------------------------------------------------------------+
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
   if(DailyDrawdownPct <= 0.0 || g_dayStartEquity <= 0.0)
      return false;
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

//+------------------------------------------------------------------+
//| Alerts                                                            |
//+------------------------------------------------------------------+
void FireAlert(const string msg)
{
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("PhotonMS", msg);
   Print(msg);
}

//+------------------------------------------------------------------+
//| Heavy analysis — runs once per new bar                            |
//+------------------------------------------------------------------+
void RefreshStructure()
{
   int n = MathMin(AnalysisBars, Bars(_Symbol, _Period));
   if(n < SwingLength * 2 + 5)
      return;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, _Period, 0, n, r);
   if(copied <= 0)
      return;
   n = copied;

   g_swN  = 0;
   g_obN  = 0;
   g_fvgN = 0;

   // --- 1) Swings: walk oldest -> newest so g_sw[] stays chronological.
   for(int i = n - SwingLength - 1; i >= SwingLength; i--)
   {
      double hi = r[i].high;
      double lo = r[i].low;
      bool isHigh = true, isLow = true;

      for(int j = 1; j <= SwingLength && (isHigh || isLow); j++)
      {
         if(isHigh && (hi <= r[i - j].high || hi <= r[i + j].high)) isHigh = false;
         if(isLow  && (lo >= r[i - j].low  || lo >= r[i + j].low )) isLow  = false;
      }

      if(isHigh && g_swN < SWING_CAP)
      {
         g_sw[g_swN].t      = r[i].time;
         g_sw[g_swN].price  = hi;
         g_sw[g_swN].isHigh = true;
         g_sw[g_swN].shift  = i;
         g_swN++;
      }
      if(isLow && g_swN < SWING_CAP)
      {
         g_sw[g_swN].t      = r[i].time;
         g_sw[g_swN].price  = lo;
         g_sw[g_swN].isHigh = false;
         g_sw[g_swN].shift  = i;
         g_swN++;
      }
   }
   if(g_swN < 4)
      return;

   // --- 2) Trend from the last two highs and last two lows.
   double lastHi = 0, prevHi = 0, lastLo = 0, prevLo = 0;
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
   // else keep previous trend

   // --- 3) CHoCH alert on trend flip
   if(UseCHoCH && g_prevTrend != TREND_NONE && g_trend != TREND_NONE
      && g_trend != g_prevTrend)
   {
      FireAlert(StringFormat("%s %s CHoCH on %s",
                             _Symbol,
                             (g_trend == TREND_UP ? "BULLISH" : "BEARISH"),
                             EnumToString((ENUM_TIMEFRAMES)_Period)));
   }

   // --- 4) Order Blocks: walk swings, find BOS, mark last opposing candle.
   if(UseOrderBlocks)
   {
      double trackedHigh = 0, trackedLow = 0;
      for(int s = 0; s < g_swN; s++)
      {
         if(g_sw[s].isHigh)
         {
            if(trackedHigh > 0.0 && g_sw[s].price > trackedHigh)
            {
               int sIdx = g_sw[s].shift;
               for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
               {
                  if(r[k].close < r[k].open && g_obN < ZONE_CAP)
                  {
                     g_ob[g_obN].t       = r[k].time;
                     g_ob[g_obN].top     = MathMax(r[k].open, r[k].close);
                     g_ob[g_obN].bot     = r[k].low;
                     g_ob[g_obN].bullish = true;
                     g_ob[g_obN].dead    = false;
                     g_ob[g_obN].shift   = k;
                     g_obN++;
                     break;
                  }
               }
            }
            trackedHigh = g_sw[s].price;
         }
         else
         {
            if(trackedLow > 0.0 && g_sw[s].price < trackedLow)
            {
               int sIdx = g_sw[s].shift;
               for(int k = sIdx + 1; k < n - 1 && k < sIdx + 30; k++)
               {
                  if(r[k].close > r[k].open && g_obN < ZONE_CAP)
                  {
                     g_ob[g_obN].t       = r[k].time;
                     g_ob[g_obN].top     = r[k].high;
                     g_ob[g_obN].bot     = MathMin(r[k].open, r[k].close);
                     g_ob[g_obN].bullish = false;
                     g_ob[g_obN].dead    = false;
                     g_ob[g_obN].shift   = k;
                     g_obN++;
                     break;
                  }
               }
            }
            trackedLow = g_sw[s].price;
         }
      }
   }

   // --- 5) FVGs: 3-bar imbalances
   if(UseFVG)
   {
      for(int i = 2; i < n - 1 && g_fvgN < ZONE_CAP; i++)
      {
         if(r[i + 2].high < r[i].low)        // bullish gap
         {
            g_fvg[g_fvgN].t       = r[i + 1].time;
            g_fvg[g_fvgN].top     = r[i].low;
            g_fvg[g_fvgN].bot     = r[i + 2].high;
            g_fvg[g_fvgN].bullish = true;
            g_fvg[g_fvgN].dead    = false;
            g_fvg[g_fvgN].shift   = i + 1;
            g_fvgN++;
         }
         else if(r[i + 2].low > r[i].high)   // bearish gap
         {
            g_fvg[g_fvgN].t       = r[i + 1].time;
            g_fvg[g_fvgN].top     = r[i + 2].low;
            g_fvg[g_fvgN].bot     = r[i].high;
            g_fvg[g_fvgN].bullish = false;
            g_fvg[g_fvgN].dead    = false;
            g_fvg[g_fvgN].shift   = i + 1;
            g_fvgN++;
         }
      }
   }

   // --- 6) Mitigation — mark zones already tagged by later price action.
   MarkZoneMitigation(g_ob,  g_obN,  r, n);
   MarkZoneMitigation(g_fvg, g_fvgN, r, n);

   // --- 7) Age out zones beyond MaxZoneAgeBars
   for(int i = 0; i < g_obN;  i++) if(g_ob[i].shift  > MaxZoneAgeBars) g_ob[i].dead  = true;
   for(int i = 0; i < g_fvgN; i++) if(g_fvg[i].shift > MaxZoneAgeBars) g_fvg[i].dead = true;

   // --- 8) Liquidity sweep on the just-closed bar (index 1)
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
         FireAlert(StringFormat("%s SELL liquidity sweep above %s",
                                _Symbol, DoubleToString(recentHi, _Digits)));
      if(recentLo > 0 && l1 < recentLo && c1 > recentLo)
         FireAlert(StringFormat("%s BUY liquidity sweep below %s",
                                _Symbol, DoubleToString(recentLo, _Digits)));
   }
}

//+------------------------------------------------------------------+
//| For each zone, scan bars newer than its origin; first to tag it   |
//| against its bias marks it dead (mitigated/filled).                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Helper: does any unfilled FVG overlap with this OB?               |
//+------------------------------------------------------------------+
bool HasFVGInside(const Zone &ob)
{
   for(int z = 0; z < g_fvgN; z++)
   {
      if(g_fvg[z].dead) continue;
      if(g_fvg[z].bullish != ob.bullish) continue;
      if(g_fvg[z].top >= ob.bot && g_fvg[z].bot <= ob.top)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Entry: tap-into-OB                                                 |
//+------------------------------------------------------------------+
void TryEnter()
{
   if(g_haltedToday || DailyHalted()) return;
   if(CountMyOpenTrades() >= MaxConcurrentTrades) return;

   if(!gSym.RefreshRates()) return;
   double spread = (gSym.Ask() - gSym.Bid()) / _Point;
   if(MaxSpreadPoints > 0 && spread > MaxSpreadPoints) return;

   double bid = gSym.Bid();
   double ask = gSym.Ask();

   for(int z = 0; z < g_obN; z++)
   {
      if(g_ob[z].dead) continue;
      if(RequireFVGInOB && !HasFVGInside(g_ob[z])) continue;

      if(g_ob[z].bullish)
      {
         if(RequireTrendAgree && g_trend == TREND_DOWN) continue;
         if(bid <= g_ob[z].top && bid >= g_ob[z].bot)
         {
            OpenTrade(true, g_ob[z]);
            g_ob[z].dead = true;
            return;                 // one entry per tick
         }
      }
      else
      {
         if(RequireTrendAgree && g_trend == TREND_UP) continue;
         if(ask >= g_ob[z].bot && ask <= g_ob[z].top)
         {
            OpenTrade(false, g_ob[z]);
            g_ob[z].dead = true;
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open a trade with SL beyond the OB and TP at RR multiple          |
//+------------------------------------------------------------------+
void OpenTrade(bool buy, const Zone &ob)
{
   double padding = SLPaddingPoints * _Point;
   double entry, sl, tp, riskDist;

   if(buy)
   {
      entry    = gSym.Ask();
      sl       = ob.bot - padding;
      riskDist = entry - sl;
      if(riskDist <= 0) return;
      tp       = entry + RewardToRisk * riskDist;
   }
   else
   {
      entry    = gSym.Bid();
      sl       = ob.top + padding;
      riskDist = sl - entry;
      if(riskDist <= 0) return;
      tp       = entry - RewardToRisk * riskDist;
   }

   double lots = CalcLots(riskDist);
   if(lots <= 0) return;

   string side = buy ? "BUY" : "SELL";
   string msg = StringFormat("%s %s %s @%s  SL=%s  TP=%s  lots=%.2f",
                             AlertsOnly ? "[SIM]" : "[LIVE]",
                             _Symbol, side,
                             DoubleToString(entry, _Digits),
                             DoubleToString(sl, _Digits),
                             DoubleToString(tp, _Digits),
                             lots);
   FireAlert(msg);

   if(AlertsOnly) return;

   bool ok = buy
      ? gTrade.Buy (lots, _Symbol, entry, sl, tp, "MS_OB")
      : gTrade.Sell(lots, _Symbol, entry, sl, tp, "MS_OB");
   if(!ok)
      Print("Order failed: ", gTrade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Position sizing — % equity risk                                   |
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || slDistancePrice <= 0) return 0;

   double lossPerLot = slDistancePrice / tickSize * tickValue;
   if(lossPerLot <= 0) return 0;

   double lots    = riskMoney / lossPerLot;
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));
   return lots;
}

//+------------------------------------------------------------------+
int CountMyOpenTrades()
{
   int total = PositionsTotal(), c = 0;
   for(int i = 0; i < total; i++)
   {
      if(gPos.SelectByIndex(i) && gPos.Magic() == MagicNumber
         && gPos.Symbol() == _Symbol)
         c++;
   }
   return c;
}

//+------------------------------------------------------------------+
//| Markup: redraw once per new bar                                   |
//+------------------------------------------------------------------+
void RedrawMarkup()
{
   ObjectsDeleteAll(0, OBJP);

   // swings
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

   datetime tEnd = iTime(_Symbol, _Period, 0) + PeriodSeconds() * 20;

   // order blocks
   for(int z = 0; z < g_obN; z++)
   {
      if(g_ob[z].dead) continue;
      string nm = OBJP + "OB_" + IntegerToString(z);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_ob[z].t, g_ob[z].top, tEnd, g_ob[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      g_ob[z].bullish ? clrTeal : clrFireBrick);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
   }

   // fvgs
   for(int z = 0; z < g_fvgN; z++)
   {
      if(g_fvg[z].dead) continue;
      string nm = OBJP + "FVG_" + IntegerToString(z);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_fvg[z].t, g_fvg[z].top, tEnd, g_fvg[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      g_fvg[z].bullish ? clrDarkGreen : clrDarkRed);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
   }

   // trend tag (top-left corner of price)
   string tn = OBJP + "TREND";
   ObjectCreate(0, tn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tn, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tn, OBJPROP_XDISTANCE,  10);
   ObjectSetInteger(0, tn, OBJPROP_YDISTANCE,  20);
   ObjectSetInteger(0, tn, OBJPROP_COLOR,
                    g_trend == TREND_UP ? clrLimeGreen :
                    g_trend == TREND_DOWN ? clrRed : clrGray);
   ObjectSetString (0, tn, OBJPROP_TEXT,
                    g_trend == TREND_UP   ? "TREND: UP"   :
                    g_trend == TREND_DOWN ? "TREND: DOWN" : "TREND: -");
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
