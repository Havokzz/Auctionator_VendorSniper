# Changelog

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
