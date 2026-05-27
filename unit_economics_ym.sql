-- представление с подробной стоимостью услуг яндекса

DROP VIEW IF EXISTS yandex.v_order_pnl_detailed;

CREATE VIEW yandex.v_order_pnl_detailed AS
WITH order_sku_counts AS (
    SELECT order_id, COUNT(*) as sku_count
    FROM yandex.order_finance
    GROUP BY order_id
),
ranked_transactions AS (
    SELECT DISTINCT ON (ot.id)
        ot.order_id,
        ot.shop_sku,
        ot.transaction_sum,
        conf.target_column,
        conf.financial_group
    FROM yandex.order_transactions ot
    JOIN yandex.finance_config conf ON 
        TRIM(LOWER(ot.transaction_source)) = TRIM(LOWER(conf.yandex_source)) 
        AND (
            conf.yandex_service IS NULL 
            OR TRIM(LOWER(ot.offer_or_service_name)) = TRIM(LOWER(conf.yandex_service))
        )
        AND (
            conf.yandex_payment_status IS NULL 
            OR TRIM(LOWER(ot.payment_status)) = TRIM(LOWER(conf.yandex_payment_status))
        )
    ORDER BY ot.id, (CASE WHEN conf.yandex_service IS NOT NULL THEN 1 ELSE 2 END) ASC
),
aggregated_raw AS (
    SELECT 
        order_id,
        shop_sku,
        SUM(transaction_sum) FILTER (WHERE target_column = 'tl_paid_rub') as tl_paid_rub,
        SUM(transaction_sum) FILTER (WHERE target_column = 'tl_pending_amount') as tl_pending_amount,
        SUM(transaction_sum) FILTER (WHERE target_column = 'tl_compensation') as tl_compensation,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_inc_plus') as pnt_inc_plus,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_inc_market') as pnt_inc_market,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_inc_delivery') as pnt_inc_delivery,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_inc_rev_joint_promo') as pnt_inc_rev_joint_promo,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_rev_market') as pnt_exp_rev_market,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_rev_plus') as pnt_exp_rev_plus,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_listing') as pnt_exp_listing,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_late_ship') as pnt_exp_late_ship,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_cancel') as pnt_exp_cancel,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_boost') as pnt_exp_boost,
        SUM(transaction_sum) FILTER (WHERE target_column = 'pnt_exp_avg_mile') as pnt_exp_avg_mile,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_loyalty_program') as act_loyalty_program,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_avg_mile') as act_avg_mile,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_delivery_customer') as act_delivery_customer,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_placement_fee_rub') as act_placement_fee_rub,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_payment_transfer') as act_payment_transfer,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_boost_fee_rub') as act_boost_fee_rub,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_payment_acceptance') as act_payment_acceptance,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_unclaimed_return') as act_unclaimed_return,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_express_delivery') as act_express_delivery,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_delay_fee') as act_delay_fee,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_cancelletion_fee') as act_cancelletion_fee,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_loyalty_discount') as act_loyalty_discount,
        SUM(transaction_sum) FILTER (WHERE target_column = 'act_boost_fee_bonus') as act_boost_fee_bonus
    FROM ranked_transactions
    GROUP BY order_id, shop_sku
),
final_calculation AS (
    SELECT 
        f.id as finance_id,
        (COALESCE(ar_s.tl_paid_rub, 0) + COALESCE(ar_o.tl_paid_rub / NULLIF(osc.sku_count, 0), 0)) as tl_paid_rub,
        (COALESCE(ar_s.tl_pending_amount, 0) + COALESCE(ar_o.tl_pending_amount / NULLIF(osc.sku_count, 0), 0)) as tl_pending_amount,
        (COALESCE(ar_s.tl_compensation, 0) + COALESCE(ar_o.tl_compensation / NULLIF(osc.sku_count, 0), 0)) as tl_compensation,
        (COALESCE(ar_s.pnt_inc_plus, 0) + COALESCE(ar_o.pnt_inc_plus / NULLIF(osc.sku_count, 0), 0)) as pnt_inc_plus,
        (COALESCE(ar_s.pnt_inc_market, 0) + COALESCE(ar_o.pnt_inc_market / NULLIF(osc.sku_count, 0), 0)) as pnt_inc_market,
        (COALESCE(ar_s.pnt_inc_delivery, 0) + COALESCE(ar_o.pnt_inc_delivery / NULLIF(osc.sku_count, 0), 0)) as pnt_inc_delivery,
        (COALESCE(ar_s.pnt_inc_rev_joint_promo, 0) + COALESCE(ar_o.pnt_inc_rev_joint_promo / NULLIF(osc.sku_count, 0), 0)) as pnt_inc_rev_joint_promo,
        (COALESCE(ar_s.pnt_exp_rev_market, 0) + COALESCE(ar_o.pnt_exp_rev_market / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_rev_market,
        (COALESCE(ar_s.pnt_exp_rev_plus, 0) + COALESCE(ar_o.pnt_exp_rev_plus / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_rev_plus,
        (COALESCE(ar_s.pnt_exp_listing, 0) + COALESCE(ar_o.pnt_exp_listing / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_listing,
        (COALESCE(ar_s.pnt_exp_late_ship, 0) + COALESCE(ar_o.pnt_exp_late_ship / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_late_ship,
        (COALESCE(ar_s.pnt_exp_cancel, 0) + COALESCE(ar_o.pnt_exp_cancel / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_cancel,
        (COALESCE(ar_s.pnt_exp_boost, 0) + COALESCE(ar_o.pnt_exp_boost / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_boost,
        (COALESCE(ar_s.pnt_exp_avg_mile, 0) + COALESCE(ar_o.pnt_exp_avg_mile / NULLIF(osc.sku_count, 0), 0)) as pnt_exp_avg_mile,
        (COALESCE(ar_s.act_loyalty_program, 0) + COALESCE(ar_o.act_loyalty_program / NULLIF(osc.sku_count, 0), 0)) as act_loyalty_program,
        (COALESCE(ar_s.act_avg_mile, 0) + COALESCE(ar_o.act_avg_mile / NULLIF(osc.sku_count, 0), 0)) as act_avg_mile,
        (COALESCE(ar_s.act_delivery_customer, 0) + COALESCE(ar_o.act_delivery_customer / NULLIF(osc.sku_count, 0), 0)) as act_delivery_customer,
        (COALESCE(ar_s.act_placement_fee_rub, 0) + COALESCE(ar_o.act_placement_fee_rub / NULLIF(osc.sku_count, 0), 0)) as act_placement_fee_rub,
        (COALESCE(ar_s.act_payment_transfer, 0) + COALESCE(ar_o.act_payment_transfer / NULLIF(osc.sku_count, 0), 0)) as act_payment_transfer,
        (COALESCE(ar_s.act_boost_fee_rub, 0) + COALESCE(ar_o.act_boost_fee_rub / NULLIF(osc.sku_count, 0), 0)) as act_boost_fee_rub,
        (COALESCE(ar_s.act_payment_acceptance, 0) + COALESCE(ar_o.act_payment_acceptance / NULLIF(osc.sku_count, 0), 0)) as act_payment_acceptance,
        (COALESCE(ar_s.act_unclaimed_return, 0) + COALESCE(ar_o.act_unclaimed_return / NULLIF(osc.sku_count, 0), 0)) as act_unclaimed_return,
        (COALESCE(ar_s.act_express_delivery, 0) + COALESCE(ar_o.act_express_delivery / NULLIF(osc.sku_count, 0), 0)) as act_express_delivery,
        (COALESCE(ar_s.act_delay_fee, 0) + COALESCE(ar_o.act_delay_fee / NULLIF(osc.sku_count, 0), 0)) as act_delay_fee,
        (COALESCE(ar_s.act_cancelletion_fee, 0) + COALESCE(ar_o.act_cancelletion_fee / NULLIF(osc.sku_count, 0), 0)) as act_cancelletion_fee,
        (COALESCE(ar_s.act_loyalty_discount, 0) + COALESCE(ar_o.act_loyalty_discount / NULLIF(osc.sku_count, 0), 0)) as act_loyalty_discount,
        (COALESCE(ar_s.act_boost_fee_bonus, 0) + COALESCE(ar_o.act_boost_fee_bonus / NULLIF(osc.sku_count, 0), 0)) as act_boost_fee_bonus
    FROM yandex.order_finance f
    LEFT JOIN order_sku_counts osc ON f.order_id = osc.order_id
    LEFT JOIN aggregated_raw ar_s ON f.order_id = ar_s.order_id AND TRIM(LOWER(f.sku)) = TRIM(LOWER(ar_s.shop_sku))
    LEFT JOIN aggregated_raw ar_o ON f.order_id = ar_o.order_id AND ar_o.shop_sku IS NULL
)
SELECT 
    f.order_id, f.sku, f.yandex_status, c.yandex_campaign_id,
    calc.tl_paid_rub, calc.tl_pending_amount, calc.tl_compensation,
    calc.act_placement_fee_rub, calc.act_boost_fee_rub, calc.act_delivery_customer, calc.act_avg_mile,
    calc.act_payment_acceptance, calc.act_payment_transfer, calc.act_loyalty_program, calc.act_unclaimed_return,
    calc.act_express_delivery, calc.act_delay_fee, calc.act_cancelletion_fee, calc.act_loyalty_discount, calc.act_boost_fee_bonus,
    calc.pnt_inc_plus, calc.pnt_inc_market, calc.pnt_inc_delivery, calc.pnt_inc_rev_joint_promo,
    calc.pnt_exp_rev_market, calc.pnt_exp_rev_plus, calc.pnt_exp_listing, calc.pnt_exp_late_ship,
    calc.pnt_exp_cancel, calc.pnt_exp_boost, calc.pnt_exp_avg_mile
FROM yandex.order_finance f
JOIN yandex.campaigns c ON f.campaign_id = c.id
JOIN final_calculation calc ON f.id = calc.finance_id;
