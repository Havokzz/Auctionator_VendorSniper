# Changelog

## Unreleased

- Vendor Deals: after an item sells out at its current price, the deal that takes its place in the list is selected, instead of following the same item as its price goes up.
- Vendor Deals: purchases are no longer lost or miscounted when the auction house reports an error during a scan. Every confirmed purchase counts towards the session and is sold to a vendor when that option is on.
- Vendor Deals: a scan no longer stops when you buy while it runs.
- Vendor Deals: deals you can't afford are passed over, and the Buy button says when none are affordable.
- Vendor Deals: clicking a deal that gets removed says why in chat, and the list keeps the selected row in view.
- Turning off "Include disenchant value" after a scan now removes every disenchant-only deal.

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
