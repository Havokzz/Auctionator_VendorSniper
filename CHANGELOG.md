# Changelog

## 1.5.2

- Recipe items (Pattern:, Plans:, Recipe: and so on) now show the craft's profit, what it sells for and what its reagents cost, as 1.5.0 meant them to. The lines sit right under Auctionator's.
- Recipe items find the recipe on any of your characters, so you can check a pattern for your tailor while shopping on another character. The profit line names that character, and says when they already know the recipe.

## 1.5.1

- The Vendor Deals and Crafting tabs no longer sit underneath another add-on's auction house tab. When the auction house opens and another tab is in their place, they move to its right.

## 1.5.0

- **Recipe profit before you learn it**: at a profession trainer, and on recipe items (Pattern:, Plans:, Recipe: and so on) in the auction house, your bags or a vendor, the tooltip shows the craft's profit, what it sells for and what its reagents cost. Enchanting formulas show what their materials cost. Open each profession window once so the add-on knows its recipes. Recipes you haven't learned don't appear on the Crafting tab.
- **Merchant price** in item tooltips: what a merchant charges for the item, right under Auctionator's lines, and whether the auction house is cheaper. Auctionator's own Vendor line is what a merchant pays you. Shows for items you've seen at a merchant.
- Both can be turned off in the options.

## 1.4.1

- Crafting: point at a recipe's **Sells for** or **Profit** to see how the profit adds up: the auction house price, the auction house's 5% cut, what you get, the reagents and the profit.

## 1.4.0

- Vendor Deals: a **Sort** dropdown sets the list's order, which is also the order the Buy button buys in:
  - **Profit per item**: biggest profit first (as before).
  - **Return on gold**: the most profit for the gold spent first, so a 2s item making 6c comes before a 20s item making 7c. Best when your gold or your max spend runs out before the deals do.
  - **Lowest risk**: vendor deals and the safest disenchant deals first.
- Vendor Deals: **Max risk** is now on the tab, beside the Sort dropdown. Click it to change it.
- A scan started right after stopping one no longer begins at the stopped scan's percentage and sits there. It starts from 0%.

## 1.3.1

- Vendor Deals: the session total beside the Buy button is no longer cut off. It shows on two lines, with the profit on its own line (red if it's a loss).

## 1.3.0

- Stop a scan: while a scan runs, the Scan button (and Update prices on the Crafting tab) reads "Stop" and stops it. The deals found so far stay in the list. `/vsnipe stop` does the same.
- Key bindings: a new **Vendor Sniper** section in the game's key bindings has keys to buy the current deal, skip it, and start or stop a scan.

## 1.2.1

- Vendor Deals: every deal is valued at the finished scan's prices. With "Include disenchant value" on, some rows kept a value from the first pages of the scan. Two items that disenchant into the same materials could show a different worth and risk.
- Disenchant risk near 0% or 100% shows one decimal: a 0.5% risk reads 0.5% instead of 1%, and 99.5% instead of 100%.

## 1.2.0

- Disenchant risk: most gear disenchants into dust most of the time, and the rarer essences and shards make up its average value. A deal can be profitable on average and still lose money on most single items. Vendor Deals now shows how often that happens.
  - A new **Risk** column shows the chance that disenchanting one item is worth less than you paid, in green, yellow or red. Vendor deals show no risk.
  - Hovering a disenchant deal lists every possible result with its chance and value. It also shows the chance of a loss on one item and on all the units one click buys, since buying several evens out the luck.
  - The Buy button shows the risk of the auction it's about to buy.
  - New option **Max disenchant risk** (options page, or `/vsnipe maxrisk 50`): disenchant deals more likely than this to lose money aren't listed or bought. Off by default.
- Gear tooltips show what the most likely disenchant result is worth after the auction house cut. It's in orange when that's below the average.

## 1.1.0

- Buy any amount from merchants: the "how many" box starts at 1 instead of a full stack.
- Update notice: when someone in your guild or group runs a newer version of the add-on, chat says it's available.
- Scan progress moves steadily from start to finish, instead of sitting at 58% for most of the scan and then jumping to the end. The auction house can be closed once it reaches 95%.

## 1.0.2

- Vendor Deals: after an item sells out at its current price, the deal that takes its place in the list is selected, instead of following the same item as its price goes up.
- Vendor Deals: purchases are no longer lost or miscounted when the auction house reports an error during a scan. Every confirmed purchase counts towards the session and is sold to a vendor when that option is on.
- Vendor Deals: a scan no longer stops when you buy while it runs.
- Vendor Deals: deals you can't afford are passed over, and the Buy button says when none are affordable.
- Vendor Deals: clicking a deal that gets removed says why in chat, and the list keeps the selected row in view.
- Turning off "Include disenchant value" after a scan now removes every disenchant-only deal.

## 1.0.1

- New options to turn off the disenchant value in tooltips and the profit numbers in the profession window.
- The options page scrolls when its settings don't fit the window.

## 1.0.0

First public release.

- **Vendor Deals tab** in the auction house: finds auctions listed below what a vendor pays, or below their disenchant value, and buys them one click at a time. Scans are shared with Auctionator.
- **Crafting tab**: your most profitable recipes, priced from Auctionator's data, with an "Update prices" button. Clicking a recipe searches the crafted item and its materials.
- **Profession window**: each recipe shows its profit or loss; enchants show what their materials cost.
- **Sell to vendor**: items bought from Vendor Deals are sold automatically at the next merchant.
- **Sell junk automatically**: grey items are sold whenever you open a merchant.
- **Buy any amount from merchants**: right-click a stackable item to buy more than one stack at once.
- **Tooltips**: disenchant value and materials, and how many of an item each of your characters has.
- **Alt+click to disenchant** a bag item.
- **Options page** under Options > AddOns, or `/vsnipe options`.
