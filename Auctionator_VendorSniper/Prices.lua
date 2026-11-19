local _, VS = ...

-- Prices from Auctionator's official API (Auctionator.API.v1). Every call is guarded, so an Auctionator
-- problem shows up as "no price" instead of an error.

VS.Prices = {}
local Prices = VS.Prices

local function CallAPI(name, itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local fn = api and api[name]
  if not fn or not itemID then
    return nil
  end
  local ok, value = pcall(fn, VS.callerID, itemID)
  if ok then
    return value
  end
end

-- Auctionator's latest auction house price per unit, or nil.
function Prices.Auction(itemID)
  return CallAPI("GetAuctionPriceByItemID", itemID)
end

-- Days since Auctionator last saw the item on the auction house (0 = today), or nil.
function Prices.AgeDays(itemID)
  return CallAPI("GetAuctionAgeByItemID", itemID)
end

-- What a vendor charges for the item (Auctionator records it at merchants), or nil.
function Prices.VendorBuy(itemID)
  return CallAPI("GetVendorPriceByItemID", itemID)
end

-- The cheapest way to get one unit: auction house or a vendor. price, source ("AH" or "vendor"), or nil.
function Prices.Cheapest(itemID)
  local auction, vendor = Prices.Auction(itemID), Prices.VendorBuy(itemID)
  if vendor and vendor > 0 and (not auction or vendor <= auction) then
    return vendor, "vendor"
  end
  if auction and auction > 0 then
    return auction, "AH"
  end
end
