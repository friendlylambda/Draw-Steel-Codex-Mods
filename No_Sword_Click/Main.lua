-- No Sword Click
-- Disables the clickable hit area on the sword icons that appear over
-- tokens during the turn-selection phase, while keeping the swords visible.

local mod = dmhub.GetModLoading()

TokenHud.RegisterPanel{
    id = "no_sword_click",
    ord = 999,
    layer = "top",
    create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end

        local patched = false

        return gui.Panel{
            width = 0,
            height = 0,
            interactable = false,
            thinkTime = 0.5,
            events = {
                think = function(element)
                    if patched then
                        return
                    end

                    if token.topsheet and token.topsheet.valid then
                        local swords = token.topsheet:GetChildrenWithClassRecursive("swords")
                        if #swords > 0 then
                            for _, child in ipairs(swords[1].children) do
                                child.events.press = function() end
                                child.interactable = false
                            end
                            patched = true
                            element.thinkTime = nil
                        end
                    end
                end,
            },
        }
    end,
}
