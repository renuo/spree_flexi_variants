module Spree
  OrderContents.class_eval do
    # Get current line item for variant if exists
    # Add variant qty to line_item
    def add(variant, quantity = 1, currency = nil, shipment = nil, ad_hoc_option_value_ids = [], product_customizations = [])
      line_item = add_to_line_item(variant, quantity, currency, shipment, ad_hoc_option_value_ids, product_customizations)
      reload_totals
      PromotionHandler::Cart.new(order, line_item).activate
      ItemAdjustments.new(line_item).update
      reload_totals
      line_item
    end

    private
      def add_to_line_item(variant, quantity, currency=nil, shipment=nil, ad_hoc_option_value_ids = [], product_customizations = [])
        line_item = grab_line_item_by_variant(variant, false, ad_hoc_option_value_ids, product_customizations)

        if line_item
          line_item.target_shipment = shipment
          line_item.quantity += quantity.to_i
          line_item.currency = currency unless currency.nil?
        else
          line_item = order.line_items.new(quantity: quantity, variant: variant)
          line_item.target_shipment = shipment

          line_item.product_customizations = product_customizations
          product_customizations.each {|pc| pc.line_item = line_item}

          product_customizations.map(&:save) # it is now safe to save the customizations we built

          # find, and add the configurations, if any.  these have not been fetched from the db yet.              line_items.first.variant_id
          # we postponed it (performance reasons) until we actaully knew we needed them
          povs=[]
          ad_hoc_option_value_ids.each do |cid|
            povs << AdHocOptionValue.find(cid)
          end

          # if we dont save the line item here, ad hoc option values wont be saved
          # I don't know why, but it turtles down to the following:
          # spree-0b5f3d4738e7/core/app/models/spree/tax_rate.rb:173
          # If we don't update tax adjustments then the ad hoc option values are save at the
          # end of this function (row 56).
          line_item.save

          line_item.ad_hoc_option_values = povs

          offset_price   = povs.map(&:price_modifier).compact.sum + product_customizations.map {|pc| pc.price(variant)}.sum

          if currency
            line_item.currency = currency unless currency.nil?
            line_item.price    = variant.price_in(currency).amount + offset_price
          else
            line_item.price    = variant.price + offset_price
          end
        end
  
        line_item.save
        line_item
      end
  
      def grab_line_item_by_variant(variant, raise_error = false, ad_hoc_option_value_ids = [], product_customizations = [])
        line_item = order.find_line_item_by_variant(variant, ad_hoc_option_value_ids, product_customizations)

        if !line_item.present? && raise_error
          raise ActiveRecord::RecordNotFound, "Line item not found for variant #{variant.sku}"
        end

        line_item
      end
  end
end
