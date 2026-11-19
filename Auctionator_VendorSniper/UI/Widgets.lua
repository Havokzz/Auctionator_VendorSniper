local _, VS = ...

-- Small helpers for building frames.

VS.UI = {}
local UI = VS.UI

function UI.Button(parent, text, width, height)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, height or 22)
  button:SetText(text)
  return button
end

function UI.Text(parent, font, justify)
  local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  text:SetJustifyH(justify or "LEFT")
  text:SetWordWrap(false)
  return text
end

function UI.Background(frame, r, g, b, a)
  local texture = frame:CreateTexture(nil, "BACKGROUND")
  texture:SetAllPoints()
  texture:SetColorTexture(r or 0, g or 0, b or 0, a or 0.35)
  return texture
end

-- The area of the auction house window our tabs use: below the title bar, above the bottom edge.
function UI.AnchorInAuctionHouse(frame)
  frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 10, -28)
  frame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 28)
end

function UI.TimeAgo(seconds)
  if seconds < 60 then
    return "just now"
  elseif seconds < 3600 then
    return ("%d min ago"):format(math.floor(seconds / 60))
  end
  return ("%dh %dm ago"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end
