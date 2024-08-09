module perpetual::orders {

    use std::option::{Option};
    use aptos_framework::coin::{Self, Coin};
    use perpetual::rate::{Rate};
    use perpetual::decimal::{Self, Decimal};
    use perpetual::positions::{Position, PositionConfig};
    use perpetual::agg_price::{AggPrice};
    use perpetual::pool::{Self, OpenPositionResult, DecreasePositionResult,
        OpenPositionFailedEvent, DecreasePositionFailedEvent} ;
    use perpetual::agg_price;

    friend perpetual::market;

    const ERR_ORDER_ALREADY_EXECUTED: u64 = 1;
    const ERR_INDEX_PRICE_NOT_TRIGGERED: u64 = 2;

    struct OpenPositionOrder<phantom CoinType, phantom Fee> has store {
        executed: bool,
        created_at: u64,
        open_amount: u64,
        reserve_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        position_config: PositionConfig,
        collateral: Coin<CoinType>,
        fee: Coin<Fee>,
    }

    struct DecreasePositionOrder<phantom CoinType> has store {
        executed: bool,
        created_at: u64,
        take_profit: bool,
        decrease_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        fee: Coin<CoinType>,
    }

    // === Events ===

    struct CreateOpenPositionOrderEvent has copy, drop {
        open_amount: u64,
        reserve_amount: u64,
        limited_index_price: Decimal,
        collateral_price_threshold: Decimal,
        position_config: PositionConfig,
        collateral_amount: u64,
        fee_amount: u64,
    }

    struct CreateDecreasePositionOrderEvent has copy, drop {
        take_profit: bool,
        decrease_amount: u64,
        limited_index_price: Decimal,
        collateral_price_threshold: Decimal,
        fee_amount: u64,
    }

    public(friend) fun new_open_position_order<Collateral, Fee>(
        timestamp: u64,
        open_amount: u64,
        reserve_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        position_config: PositionConfig,
        collateral: Coin<Collateral>,
        fee: Coin<Fee>,
    ): OpenPositionOrder<Collateral, Fee> {
        let order = OpenPositionOrder<Collateral, Fee> {
            executed: false,
            created_at: timestamp,
            open_amount,
            reserve_amount,
            limited_index_price,
            collateral_price_threshold,
            position_config,
            collateral,
            fee
        };
        order
    }


    public(friend) fun new_decrease_position_order<Fee>(
        timestamp: u64,
        take_profit: bool,
        decrease_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        fee: Coin<Fee>,
    ): DecreasePositionOrder<Fee> {
        // let event = CreateDecreasePositionOrderEvent {
        //     take_profit,
        //     decrease_amount,
        //     limited_index_price: agg_price::price_of(&limited_index_price),
        //     collateral_price_threshold,
        //     fee_amount: balance::value(&fee),
        // };
        let order = DecreasePositionOrder {
            executed: false,
            created_at: timestamp,
            take_profit,
            decrease_amount,
            limited_index_price,
            collateral_price_threshold,
            fee,
        };

        // (order, event)
        order
    }

    public(friend) fun execute_open_position_order<Collateral, Index, Direction, Fee>(
        order: &mut OpenPositionOrder<Collateral, Fee>,
        rebate_rate: Rate,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (u64, Coin<Collateral>, Option<OpenPositionResult<Collateral>>, Option<OpenPositionFailedEvent>, Coin<Fee>) {
        assert!(!order.executed, ERR_ORDER_ALREADY_EXECUTED);
        let index_price = agg_price::parse_pyth_feeder(
            &pool::symbol_price_config<Index, Direction>(),
            timestamp
        );
        if (long) {
            assert!(
                decimal::le(&agg_price::price_of(&index_price), &agg_price::price_of(&order.limited_index_price)),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        } else {
            assert!(
                decimal::ge(&agg_price::price_of(&index_price), &agg_price::price_of(&order.limited_index_price)),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        };

        // update order status
        order.executed = true;
        // withdraw fee
        let fee = coin::extract_all(&mut order.fee);

        // open position in pool
        let (code, collateral, result, failure) = pool::open_position<Collateral, Index, Direction>(
            &order.position_config,
            coin::extract_all(&mut order.collateral),
            order.collateral_price_threshold,
            rebate_rate,
            long,
            order.open_amount,
            order.reserve_amount,
            lp_supply_amount,
            timestamp,
        );

        (code, collateral, result, failure, fee)
    }

    public(friend) fun execute_decrease_position_order<Collateral, Index, Direction, Fee>(
        order: &mut DecreasePositionOrder<Fee>,
        position: &mut Position<Collateral>,
        rebate_rate: Rate,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64
    ): (u64, Option<DecreasePositionResult<Collateral>>, Option<DecreasePositionFailedEvent>, Coin<Fee>) {
        assert!(!order.executed, ERR_ORDER_ALREADY_EXECUTED);
        let index_price = agg_price::parse_pyth_feeder(
            &pool::symbol_price_config<Index, Direction>(),
            timestamp
        );
        if ((long && order.take_profit) || (!long && !order.take_profit)) {
            assert!(
                decimal::ge(
                    &agg_price::price_of(&index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        } else {
            assert!(
                decimal::le(
                    &agg_price::price_of(&index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        };

        // update order status
        order.executed = true;
        // withdraw fee
        let fee = coin::extract_all(&mut order.fee);
        // decrease position in pool
        let (code, result, failure) =
            pool::decrease_position<Collateral, Index, Direction>(
                position,
                order.collateral_price_threshold,
                rebate_rate,
                long,
                order.decrease_amount,
                lp_supply_amount,
                timestamp,
        );

        (code, result, failure, fee)
    }

    public(friend) fun destroy_open_position_order<Collateral, Fee>(
        order: OpenPositionOrder<Collateral, Fee>
    ): (Coin<Collateral>, Coin<Fee>) {
        let OpenPositionOrder {
            executed: _,
            created_at: _,
            open_amount: _,
            reserve_amount: _,
            limited_index_price: _,
            collateral_price_threshold: _,
            position_config: _,
            collateral,
            fee,
        } = order;

        (collateral, fee)
    }

    public(friend) fun destory_decrease_position_order<Fee>(
        order: DecreasePositionOrder<Fee>
    ): Coin<Fee> {
        let DecreasePositionOrder {
            executed: _,
            created_at: _,
            take_profit: _,
            decrease_amount: _,
            limited_index_price: _,
            collateral_price_threshold: _,
            fee,
        } = order;

        fee
    }


}
