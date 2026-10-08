# Dashboard layout guide (Power BI)

Aim: three clean pages on a 1280 x 720 canvas, one colour theme, consistent spacing (24 pixel outer margin, 12 to 16 pixel gaps). Wireframes with exact positions are in docs/images/layout (page1, page2, page3). Positions are written as X, Y, Width, Height in pixels.

Colours: navy 12263F (header), blue 2F6FDE (main series), amber E8A33D, red D1495B, teal 1AA6B7, page background F3F5F9, card background FFFFFF, text 1F2A3C.

## A. One time setup

1. Theme. Open the Design ribbon (the tab named Design at the top of Power BI Desktop, next to View), choose Import theme, pick powerbi/theme/mortgage_mi_theme.json. A dialog confirms success. All charts now use the palette. Series order gives Up to 90 days blue, 91 to 180 days amber, Over 180 days red. Import the theme first, because importing resets report level customisations.
2. Page size. Click an empty part of the page, in the Visualizations pane choose Format page, expand Canvas settings, set Type to 16:9 and Size to 1280 x 720 (HD). Do this on each page.
3. Page background. In the same Format page area, expand Canvas background: colour F3F5F9 (More colours, Hex), Transparency 0%. Optional: set it once for all new pages through the Design ribbon, Customize theme, Page.
4. Delete the smoke test page: right click its tab at the bottom, Delete page. Only the three real pages stay.
5. Turn on the Selection pane (View tab, Selection) and Snap to grid (View tab, Gridlines and Snap to grid). The Selection pane lists every visual so you can find and rename them.

## B. How to place any visual at an exact position

1. Click the visual so its border shows.
2. Format pane, Format visual, General tab, expand Properties, then Properties. Size has Height and Width, Position has Horizontal and Vertical.
3. Type the numbers from the wireframe: Horizontal position is X, Vertical position is Y.
4. Repeat for every visual. This is slower than dragging but exact, and gives perfectly even gaps.

If you prefer dragging: select several visuals with Ctrl click, then use the Format tab on the ribbon, Align, to Align top and Distribute horizontally.

## C. Header band on every page

1. Insert tab, Shapes, Rectangle. Format shape, Style: Fill colour 12263F, Line off. Position X0, Y0, Width 1280, Height 64.
2. Insert tab, Text box. Type the page title: Page 1 "Mortgage arrears: executive overview", Page 2 "Risk and arrears by segment", Page 3 "Data quality: what was tested and what was found". Select the text, Segoe UI Semibold, size 20, colour white. Position X24, Y14, Width 800, Height 36. The text box must have no fill (Format, Effects, Background off).
3. With the rectangle selected, ribbon Format tab, Send to back, so the title and slicer sit on top of it.
4. Copy the rectangle and text box to the other pages: select both, Ctrl C, open the page, Ctrl V. They keep their position. Change only the title text.
5. Move the quarter_label slicer onto the band at X1020, Y16, Width 236, Height 34 (pages 1 and 2). Format visual, Slicer settings, Style Dropdown. Set slicer text colour and background so it reads on the band (white background, dark text is fine).

## D. Card style (all KPI cards)

1. Select a card. Format visual, General, Effects: Background on, colour FFFFFF, Visual border on, colour D5DCE8, Rounded corners 8, Shadow on (light).
2. Format visual, Visual tab, Callout value: size 28, colour 12263F. Category label: size 11, colour 5B6678.
3. Rename the label for readability: in the Visualizations pane, Fields well, right click the field, Rename for this visual. Suggested names: "Arrears accounts", "Arrears rate (accounts)", "Arrears rate (balance)", "Outstanding balance (EUR bn)", "Change in arrears accounts vs previous quarter".
4. Display units (41K showing instead of 41,018): Callout value section, Display units, set None. If you cannot find it, use the search box at the top of the Format pane and type "display". Leave this to last, it is cosmetic.
5. Format Painter: after styling one card, select it, ribbon Home, Format painter, click the next card. Repeat for all cards.

## E. Charts and tables

1. Title on for every chart (Format visual, General, Title). Use plain titles: "Arrears rate by segment", "Market arrears rate over time", "Accounts in arrears by age", "Over 180 days share by segment", "Rules run by dimension and status".
2. Bar charts: use the theme blue. Format visual, Visual tab, Bars, Colours. To remove clutter, turn off gridlines (Format visual, Visual, Gridlines) and add data labels (Data labels on).
3. Trend line charts: Format visual, Visual, X axis, Title off. If a horizontal scrollbar appears and only some quarters show, make the chart wider as in the wireframe, set the X axis label size to 8, and look in the X axis section for a Layout or Minimum category width option. The page 3 charts and tables are not affected.
4. DQ status colours: on the Rules Run by dimension chart, set pass to green 3F9E6B, warn to amber E8A33D, info to blue 2F6FDE (Format visual, Visual, Bars, Colours, pick a series).
5. Tables: Format visual, Visual tab, Style presets, choose Minimal or Alternating rows. Turn Totals off on the dq_rule table, the issue log and the reconciliation table (use the search box, type "total"). Keep Totals on for the segment tables, where the total row is meaningful. Rename columns for this visual: "Sum of rows_tested" to "Rows tested", "Sum of rows_failed" to "Rows failed".
6. Issue log table: widen the issue column by dragging its header edge, and turn Text wrap on (Format visual, Visual, Grid or Values, Text wrapping) so the long text is readable.
7. Page 3 text box: font size 11, colour 5B6678, position as in wireframe.

## F. Interactions and slicer defaults (do not skip)

1. On pages 1 and 2, select the quarter_label slicer, Format tab on the ribbon, Edit interactions, and set None on the trend line and the stacked column chart so they keep showing every quarter. Leave the other visuals on Filter.
2. Choose 2025 Q4 in the quarter slicer on each page before saving.
3. The Completeness Note should read "2025 Q4: 4 of 4 segments reported." If it says otherwise, the slicer is not on 2025 Q4.

## G. Screenshots

1. View tab, Page view, Fit to page. Close the Filters pane and the Fields pane if you want a clean screenshot (View tab, untick Filters pane).
2. Windows key + Shift + S, drag around the white canvas only, save the image as PNG.
3. Save into docs/images with the exact names page1_executive_overview.png, page2_risk_and_arrears.png and page3_data_quality.png.
4. Save the file as powerbi/mortgage_mi.pbix.
