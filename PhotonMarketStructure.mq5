//+------------------------------------------------------------------+
//|                                      PhotonMarketStructure.mq5   |
//|                                      Generated for MT5           |
//+------------------------------------------------------------------+
#property copyright "Market Structure Assistant"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
input int   SwingLength       = 5;           // Lookback/Lookforward bars to confirm a swing
input bool  ShowBOS           = true;        // Draw Break-of-Structure lines
input bool  ProcessOnBarClose = true;        // Run on new bar only (skip mid-bar ticks)
input color UpColor           = clrLimeGreen;
input color DnColor           = clrRed;

//--- Object name prefix so cleanup is a single call
const string OBJ_PREFIX = "MS_";

//--- Cached state across ticks
double   g_lastSwingHigh    = 0.0;
double   g_lastSwingLow     = 0.0;
datetime g_lastHighTime     = 0;
datetime g_lastLowTime      = 0;
datetime g_lastProcessedTime= 0;   // newest confirmable bar we visited
datetime g_lastBarTime      = 0;   // gate for ProcessOnBarClose

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "PhotonMarketStructure");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create-or-move a swing text label with non-interactive props      |
//+------------------------------------------------------------------+
void DrawSwingLabel(const string name,
                    const datetime t,
                    const double price,
                    const string text,
                    const color clr,
                    const ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
}

//+------------------------------------------------------------------+
//| Create-or-move a BOS trend line                                   |
//+------------------------------------------------------------------+
void DrawBOSLine(const string name,
                 const datetime t1, const double p1,
                 const datetime t2, const double p2,
                 const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   }
   else
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   // Need at least 2*SwingLength + 1 bars before any swing can be confirmed
   const int minBars = SwingLength * 2 + 1;
   if(rates_total < minBars)
      return 0;

   // Series-indexed view: index 0 = newest bar
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);

   // Confirmed swings only change when a new confirmable bar appears.
   // Gate per-tick work behind a bar-time check.
   const datetime confirmableNewest = time[SwingLength];
   if(ProcessOnBarClose && prev_calculated > 0 &&
      confirmableNewest == g_lastBarTime)
      return rates_total;
   g_lastBarTime = confirmableNewest;

   // Decide between full and incremental scan
   bool fullScan = (prev_calculated == 0 || g_lastProcessedTime == 0);
   int  startIdx;

   if(!fullScan)
   {
      // New bars added since last call; resume just below them
      const int newBars = rates_total - prev_calculated;
      startIdx = SwingLength + (newBars > 0 ? newBars - 1 : 0);

      // Verify continuity with the last processed timestamp; if the
      // history was rebuilt/refreshed, fall back to a full scan.
      const int verifyIdx = startIdx + 1;
      if(verifyIdx >= rates_total || time[verifyIdx] != g_lastProcessedTime)
         fullScan = true;
   }

   if(fullScan)
   {
      g_lastSwingHigh = 0.0;
      g_lastSwingLow  = 0.0;
      g_lastHighTime  = 0;
      g_lastLowTime   = 0;
      startIdx        = rates_total - SwingLength - 1;
   }

   // Clamp
   if(startIdx > rates_total - SwingLength - 1)
      startIdx = rates_total - SwingLength - 1;
   if(startIdx < SwingLength)
      return rates_total;

   // Walk from oldest unprocessed confirmable bar -> newest confirmable bar
   for(int i = startIdx; i >= SwingLength; i--)
   {
      const double hi = high[i];
      const double lo = low[i];
      const datetime t = time[i];

      // --- Swing High: strictly higher than SwingLength bars on each side
      bool isSwingHigh = true;
      for(int j = 1; j <= SwingLength; j++)
      {
         if(hi <= high[i - j] || hi <= high[i + j])
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         string label;
         if(g_lastSwingHigh > 0.0)
            label = (hi > g_lastSwingHigh) ? "HH" : "LH";
         else
            label = "H";

         const string timeStr = TimeToString(t, TIME_DATE | TIME_MINUTES);

         if(ShowBOS && g_lastSwingHigh > 0.0 && hi > g_lastSwingHigh)
         {
            DrawBOSLine(OBJ_PREFIX + "BOSH_" + timeStr,
                        g_lastHighTime, g_lastSwingHigh,
                        t,              g_lastSwingHigh,
                        UpColor);
         }

         DrawSwingLabel(OBJ_PREFIX + "H_" + timeStr,
                        t, hi, label, UpColor, ANCHOR_LOWER);

         g_lastSwingHigh = hi;
         g_lastHighTime  = t;
      }

      // --- Swing Low: strictly lower than SwingLength bars on each side
      bool isSwingLow = true;
      for(int j = 1; j <= SwingLength; j++)
      {
         if(lo >= low[i - j] || lo >= low[i + j])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow)
      {
         string label;
         if(g_lastSwingLow > 0.0)
            label = (lo < g_lastSwingLow) ? "LL" : "HL";
         else
            label = "L";

         const string timeStr = TimeToString(t, TIME_DATE | TIME_MINUTES);

         if(ShowBOS && g_lastSwingLow > 0.0 && lo < g_lastSwingLow)
         {
            DrawBOSLine(OBJ_PREFIX + "BOSL_" + timeStr,
                        g_lastLowTime, g_lastSwingLow,
                        t,             g_lastSwingLow,
                        DnColor);
         }

         DrawSwingLabel(OBJ_PREFIX + "L_" + timeStr,
                        t, lo, label, DnColor, ANCHOR_UPPER);

         g_lastSwingLow = lo;
         g_lastLowTime  = t;
      }

      g_lastProcessedTime = t;
   }

   // One redraw per OnCalculate instead of per-object
   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
