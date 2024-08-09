module perpetual::positions {

    use std::option::{Self, Option};
    use aptos_framework::coin::{Self, Coin};
    use perpetual::rate::{Self, Rate};
    use perpetual::srate::{Self, SRate};
    use perpetual::decimal::{Self, Decimal};
    use perpetual::agg_price::{Self, AggPrice};
    use perpetual::sdecimal::{Self, SDecimal};

    friend perpetual::market;
    friend perpetual::pool;

    const OK: u64 = 0;

    const ERR_ALREADY_CLOSED: u64 = 1;
    const ERR_POSITION_NOT_CLOSED: u64 = 2;
    const ERR_INVALID_PLEDGE: u64 = 3;
    const ERR_INVALID_REDEEM_AMOUNT: u64 = 4;
    const ERR_INVALID_OPEN_AMOUNT: u64 = 5;
    const ERR_INVALID_DECREASE_AMOUNT: u64 = 6;
    const ERR_INSUFFICIENT_COLLATERAL: u64 = 7;
    const ERR_INSUFFICIENT_RESERVED: u64 = 8;
    const ERR_COLLATERAL_VALUE_TOO_LESS: u64 = 9;
    const ERR_HOLDING_DURATION_TOO_SHORT: u64 = 10;
    const ERR_LEVERAGE_TOO_LARGE: u64 = 11;
    const ERR_LIQUIDATION_TRIGGERED: u64 = 12;
    const ERR_LIQUIDATION_NOT_TRIGGERED: u64 = 13;
    const ERR_EXCEED_MAX_RESERVED: u64 = 14;
    const ERR_COLLATERAL_PRICE_EXCEED_THRESHOLD: u64 = 15;

    struct PositionConfig has copy, drop, store {
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: Decimal,
        open_fee_bps: Rate,
        decrease_fee_bps: Rate,
        // liquidation_threshold + liquidation_bonus < 100%
        liquidation_threshold: Rate,
        liquidation_bonus: Rate,
    }

    struct Position<phantom CoinType> has store {
        closed: bool,
        config: PositionConfig,
        open_timestamp: u64,
        position_amount: u64,
        position_size: Decimal,
        reserving_fee_amount: Decimal,
        funding_fee_value: SDecimal,
        last_reserving_rate: Rate,
        last_funding_rate: SRate,
        reserved: Coin<CoinType>,
        collateral: Coin<CoinType>,
    }

    struct OpenPositionResult<phantom Collateral> {
        position: Position<Collateral>,
        open_fee: Coin<Collateral>,
        open_fee_amount: Decimal,
    }

    struct DecreasePositionResult<phantom Collateral> {
        closed: bool,
        has_profit: bool,
        settled_amount: u64,
        decreased_reserved_amount: u64,
        decrease_size: Decimal,
        reserving_fee_amount: Decimal,
        decrease_fee_value: Decimal,
        reserving_fee_value: Decimal,
        funding_fee_value: SDecimal,
        to_vault: Coin<Collateral>,
        to_trader: Coin<Collateral>,
    }

    public(friend) fun new_position_config(
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128,
    ): PositionConfig {
        PositionConfig {
            max_leverage,
            min_holding_duration,
            max_reserved_multiplier,
            min_collateral_value: decimal::from_raw(min_collateral_value),
            open_fee_bps: rate::from_raw(open_fee_bps),
            decrease_fee_bps: rate::from_raw(decrease_fee_bps),
            liquidation_threshold: rate::from_raw(liquidation_threshold),
            liquidation_bonus: rate::from_raw(liquidation_bonus),
        }
    }

    public(friend) fun open_position<Collateral>(
        config: &PositionConfig,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        liquidity: &mut Coin<Collateral>,
        collateral: &mut Coin<Collateral>,
        collateral_price_threshold: Decimal,
        open_amount: u64,
        reserve_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): (u64, Option<OpenPositionResult<Collateral>>) {
        if (coin::value(collateral) == 0) {
            return (ERR_INVALID_PLEDGE, option::none())
        };
        if (
            decimal::lt(
                &agg_price::price_of(collateral_price),
                &collateral_price_threshold,
            )
        ) {
            return (ERR_COLLATERAL_PRICE_EXCEED_THRESHOLD, option::none())
        };
        if (open_amount == 0) {
            return (ERR_INVALID_OPEN_AMOUNT, option::none())
        };
        if (coin::value(collateral) * config.max_reserved_multiplier < reserve_amount) {
            return (ERR_EXCEED_MAX_RESERVED, option::none())
        };

        // compute position size
        let open_size = agg_price::coins_to_value(index_price, open_amount);

        // compute fee
        let open_fee_value = decimal::mul_with_rate(open_size, config.open_fee_bps);
        let open_fee_amount_dec = agg_price::value_to_coins(collateral_price, open_fee_value);
        let open_fee_amount = decimal::ceil_u64(open_fee_amount_dec);
        if (open_fee_amount > coin::value(collateral)) {
            return (ERR_INSUFFICIENT_COLLATERAL, option::none())
        };

        // compute collateral value
        let collateral_value = agg_price::coins_to_value(
            collateral_price,
            coin::value(collateral) - open_fee_amount,
        );
        if (decimal::lt(&collateral_value, &config.min_collateral_value)) {
            return (ERR_COLLATERAL_VALUE_TOO_LESS, option::none())
        };

        // validate leverage
        let ok = check_leverage(config, collateral_value, open_amount, index_price);
        if (!ok) {
            return (ERR_LEVERAGE_TOO_LARGE, option::none())
        };

        // take away open fee
        let open_fee = coin::extract(collateral, open_fee_amount);

        // construct position
        let position = Position {
            closed: false,
            config: *config,
            open_timestamp: timestamp,
            position_amount: open_amount,
            position_size: open_size,
            reserving_fee_amount: decimal::zero(),
            funding_fee_value: sdecimal::zero(),
            last_reserving_rate: reserving_rate,
            last_funding_rate: funding_rate,
            reserved: coin::extract(liquidity, reserve_amount),
            collateral: coin::extract_all(collateral),
        };

        let result = OpenPositionResult {
            position,
            open_fee,
            open_fee_amount: open_fee_amount_dec,
        };
        (OK, option::some(result))
    }

    public(friend) fun decrease_position<Collateral>(
        position: &mut Position<Collateral>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        collateral_price_threshold: Decimal,
        long: bool,
        decrease_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): (u64, Option<DecreasePositionResult<Collateral>>) {
        if (position.closed) {
            return (ERR_ALREADY_CLOSED, option::none())
        };
        if (
            decimal::lt(
                &agg_price::price_of(collateral_price),
                &collateral_price_threshold,
            )
        ) {
            return (ERR_COLLATERAL_PRICE_EXCEED_THRESHOLD, option::none())
        };
        if (
            decrease_amount == 0 || decrease_amount > position.position_amount
        ) {
            return (ERR_INVALID_DECREASE_AMOUNT, option::none())
        };

        let decrease_size = decimal::div_by_u64(
            decimal::mul_with_u64(position.position_size, decrease_amount),
            position.position_amount,
        );

        // compute delta size
        let delta_size = compute_delta_size(position, index_price, long);
        let settled_delta_size = sdecimal::div_by_u64(
            sdecimal::mul_with_u64(delta_size, decrease_amount),
            position.position_amount,
        );
        delta_size = sdecimal::sub(delta_size, settled_delta_size);

        // check holding duration
        let ok = check_holding_duration(position, &delta_size, timestamp);
        if (!ok) {
            return (ERR_HOLDING_DURATION_TOO_SHORT, option::none())
        };

        // compute fee
        let reserving_fee_amount = compute_reserving_fee_amount(position, reserving_rate);
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(reserving_fee_amount),
        );
        let funding_fee_value = compute_funding_fee_value(position, funding_rate);
        let decrease_fee_value = decimal::mul_with_rate(
            decrease_size,
            position.config.decrease_fee_bps,
        );

        // impact fee on settled delta size
        settled_delta_size = sdecimal::sub(
            settled_delta_size,
            sdecimal::add_with_decimal(
                funding_fee_value,
                decimal::add(decrease_fee_value, reserving_fee_value),
            ),
        );

        let closed = decrease_amount == position.position_amount;

        // handle settlement
        let has_profit = sdecimal::is_positive(&settled_delta_size);
        let settled_amount = agg_price::value_to_coins(
            collateral_price,
            sdecimal::value(&settled_delta_size),
        );
        let settled_amount = if (has_profit) {
            let profit_amount = decimal::floor_u64(settled_amount);
            if (profit_amount >= coin::value(&position.reserved)) {
                // should close position if reserved is not enough to pay profit
                closed = true;
                profit_amount = coin::value(&position.reserved);
            };

            profit_amount
        } else {
            let loss_amount = decimal::ceil_u64(settled_amount);
            if (loss_amount >= coin::value(&position.collateral)) {
                // should close position if collateral is not enough to pay loss
                closed = true;
                loss_amount = coin::value(&position.collateral);
            };

            loss_amount
        };
        let decreased_reserved_amount = if (closed) {
            coin::value(&position.reserved)
        } else {
            if (has_profit) { settled_amount } else { 0 }
        };

        let position_amount = position.position_amount - decrease_amount;
        let position_size = decimal::sub(position.position_size, decrease_size);

        // should check the position if not closed
        if (!closed) {
            // compute collateral value
            let collateral_value = agg_price::coins_to_value(
                collateral_price,
                if (has_profit) {
                    coin::value(&position.collateral)
                } else {
                    coin::value(&position.collateral) - settled_amount
                },
            );
            if (decimal::lt(&collateral_value, &position.config.min_collateral_value)) {
                return (ERR_COLLATERAL_VALUE_TOO_LESS, option::none())
            };

            // validate leverage
            ok = check_leverage(&position.config, collateral_value, position_amount, index_price);
            if (!ok) {
                return (ERR_LEVERAGE_TOO_LARGE, option::none())
            };

            // check liquidation
            ok = check_liquidation(&position.config, collateral_value, &delta_size);
            if (ok) {
                return (ERR_LIQUIDATION_TRIGGERED, option::none())
            };
        };

        // update position
        position.closed = closed;
        position.position_amount = position_amount;
        position.position_size = position_size;
        position.reserving_fee_amount = decimal::zero();
        position.funding_fee_value = sdecimal::zero();
        position.last_funding_rate = funding_rate;
        position.last_reserving_rate = reserving_rate;

        let (to_vault, to_trader) = if (has_profit) {
            (
                coin::zero(),
                coin::extract(&mut position.reserved, settled_amount),
            )
        } else {
            (
                coin::extract(&mut position.collateral, settled_amount),
                coin::zero(),
            )
        };

        if (closed) {
            coin::merge(&mut to_vault, coin::extract_all(&mut position.reserved));
            coin::merge(&mut to_trader, coin::extract_all(&mut position.collateral));
        };

        let result = DecreasePositionResult {
            closed,
            has_profit,
            settled_amount,
            decreased_reserved_amount,
            decrease_size,
            reserving_fee_amount,
            decrease_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        };
        (OK, option::some(result))
    }

    public(friend) fun unwrap_open_position_result<C>(
        res: OpenPositionResult<C>,
    ): (Position<C>, Coin<C>, Decimal) {
        let OpenPositionResult { position, open_fee, open_fee_amount } = res;

        (position, open_fee, open_fee_amount)
    }

    public(friend) fun decrease_reserved_from_position<Collateral>(
        position: &mut Position<Collateral>,
        decrease_amount: u64,
        reserving_rate: Rate
    ): Coin<Collateral> {
        assert!(!position.closed, ERR_ALREADY_CLOSED);
        assert!(
            decrease_amount < coin::value(&position.reserved),
            ERR_INSUFFICIENT_RESERVED,
        );

        // compute fee
        let reserving_fee_amount = compute_reserving_fee_amount(position, reserving_rate);

        // update position
        position.reserving_fee_amount = reserving_fee_amount;
        position.last_reserving_rate = reserving_rate;

        coin::extract(&mut position.reserved, decrease_amount)
    }

    public(friend) fun pledge_in_position<Collateral>(
        position: &mut Position<Collateral>,
        pledge: Coin<Collateral>
    ) {
        assert!(!position.closed, ERR_ALREADY_CLOSED);
        // handle pledge
        assert!(coin::value(&pledge) > 0, ERR_INVALID_PLEDGE);
        coin::merge(&mut position.collateral, pledge);
    }

    public(friend) fun redeem_from_position<Collateral>(
        position: &mut Position<Collateral>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        redeem_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): Coin<Collateral> {
        assert!(!position.closed, ERR_ALREADY_CLOSED);
        assert!(
            redeem_amount > 0
                && redeem_amount < coin::value(&position.collateral),
            ERR_INVALID_REDEEM_AMOUNT,
        );

        // compute delta size
        let delta_size = compute_delta_size(position, index_price, long);

        // check holding duration
        let ok = check_holding_duration(position, &delta_size, timestamp);
        assert!(ok, ERR_HOLDING_DURATION_TOO_SHORT);

        // compute fee
        let reserving_fee_amount = compute_reserving_fee_amount(position, reserving_rate);
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(reserving_fee_amount),
        );
        let funding_fee_value = compute_funding_fee_value(position, funding_rate);

        // impact fee on delta size
        delta_size = sdecimal::sub(
            delta_size,
            sdecimal::add_with_decimal(funding_fee_value, reserving_fee_value),
        );

        // update position
        position.reserving_fee_amount = reserving_fee_amount;
        position.funding_fee_value = funding_fee_value;
        position.last_reserving_rate = reserving_rate;
        position.last_funding_rate = funding_rate;

        // redeem
        let redeem = coin::extract(&mut position.collateral, redeem_amount);

        // compute collateral value
        let collateral_value = agg_price::coins_to_value(
            collateral_price,
            coin::value(&position.collateral),
        );
        assert!(
            decimal::ge(&collateral_value, &position.config.min_collateral_value),
            ERR_COLLATERAL_VALUE_TOO_LESS,
        );

        // validate leverage
        ok = check_leverage(
            &position.config,
            collateral_value,
            position.position_amount,
            index_price,
        );
        assert!(ok, ERR_LEVERAGE_TOO_LARGE);

        // validate liquidation
        ok = check_liquidation(&position.config, collateral_value, &delta_size);
        assert!(!ok, ERR_LIQUIDATION_TRIGGERED);

        redeem
    }

    public(friend) fun liquidate_position<Collateral>(
        position: &mut Position<Collateral>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        reserving_rate: Rate,
        funding_rate: SRate,
    ): (
        u64,
        u64,
        u64,
        u64,
        Decimal,
        Decimal,
        Decimal,
        SDecimal,
        Coin<Collateral>,
        Coin<Collateral>,
    ) {
        assert!(!position.closed, ERR_ALREADY_CLOSED);

        // compute delta size
        let delta_size = compute_delta_size(position, index_price, long);

        // compute fee
        let reserving_fee_amount = compute_reserving_fee_amount(position, reserving_rate);
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(reserving_fee_amount),
        );
        let funding_fee_value = compute_funding_fee_value(position, funding_rate);

        // impact fee on delta size
        delta_size = sdecimal::sub(
            delta_size,
            sdecimal::add_with_decimal(funding_fee_value, reserving_fee_value),
        );

        // compute collateral value
        let collateral_value = agg_price::coins_to_value(
            collateral_price,
            coin::value(&position.collateral),
        );

        // liquidation check
        let ok = check_liquidation(&position.config, collateral_value, &delta_size);
        assert!(ok, ERR_LIQUIDATION_NOT_TRIGGERED);

        let position_amount = position.position_amount;
        let position_size = position.position_size;
        let collateral_amount = coin::value(&position.collateral);
        let reserved_amount = coin::value(&position.reserved);

        // update position
        position.closed = true;
        position.position_amount = 0;
        position.position_size = decimal::zero();
        position.reserving_fee_amount = decimal::zero();
        position.funding_fee_value = sdecimal::zero();
        position.last_funding_rate = funding_rate;
        position.last_reserving_rate = reserving_rate;

        // compute liquidation bonus
        let bonus_amount = decimal::floor_u64(
            decimal::mul_with_rate(
                decimal::from_u64(collateral_amount),
                position.config.liquidation_bonus,
            )
        );

        let to_liquidator = coin::extract(&mut position.collateral, bonus_amount);
        let to_vault = coin::extract_all(&mut position.reserved);
        coin::merge(&mut to_vault, coin::extract_all(&mut position.collateral));

        (
            bonus_amount,
            collateral_amount,
            position_amount,
            reserved_amount,
            position_size,
            reserving_fee_amount,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_liquidator,
        )
    }

    public(friend) fun destroy_position<Collateral>(position: Position<Collateral>) {
        // unwrap position
        let Position {
            closed,
            config: _,
            open_timestamp: _,
            position_amount: _,
            position_size: _,
            reserving_fee_amount: _,
            funding_fee_value: _,
            last_reserving_rate: _,
            last_funding_rate: _,
            reserved,
            collateral,
        } = position;
        assert!(closed, ERR_POSITION_NOT_CLOSED);

        coin::destroy_zero(reserved);
        coin::destroy_zero(collateral);
    }

    public fun check_leverage(
        config: &PositionConfig,
        collateral_value: Decimal,
        position_amount: u64,
        index_price: &AggPrice,
    ): bool {
        let max_size = decimal::mul_with_u64(
            collateral_value,
            config.max_leverage,
        );
        let latest_size = agg_price::coins_to_value(
            index_price,
            position_amount,
        );

        decimal::ge(&max_size, &latest_size)
    }

    public fun check_liquidation(
        config: &PositionConfig,
        collateral_value: Decimal,
        delta_size: &SDecimal,
    ): bool {
        if (sdecimal::is_positive(delta_size)) {
            false
        } else {
            decimal::le(
                &decimal::mul_with_rate(
                    collateral_value,
                    config.liquidation_threshold,
                ),
                &sdecimal::value(delta_size),
            )
        }
    }

    public fun position_size<C>(position: &Position<C>): Decimal {
        position.position_size
    }

    public fun collateral_amount<C>(position: &Position<C>): u64 {
        coin::value(&position.collateral)
    }

    // delta_size = |amount * new_price - size|
    public fun compute_delta_size<C>(
        position: &Position<C>,
        index_price: &AggPrice,
        long: bool,
    ): SDecimal {
        let latest_size = agg_price::coins_to_value(
            index_price,
            position.position_amount,
        );
        let cmp = decimal::gt(&latest_size, &position.position_size);
        let (has_profit, delta) = if (cmp) {
            (long, decimal::sub(latest_size, position.position_size))
        } else {
            (!long, decimal::sub(position.position_size, latest_size))
        };

        sdecimal::from_decimal(has_profit, delta)
    }

    public fun check_holding_duration<C>(
        position: &Position<C>,
        delta_size: &SDecimal,
        timestamp: u64,
    ): bool {
        !sdecimal::is_positive(delta_size)
            || position.open_timestamp
            + position.config.min_holding_duration <= timestamp
    }

    public fun compute_reserving_fee_amount<C>(
        position: &Position<C>,
        reserving_rate: Rate,
    ): Decimal {
        let delta_fee = decimal::mul_with_rate(
            decimal::from_u64(coin::value(&position.reserved)),
            rate::sub(reserving_rate, position.last_reserving_rate),
        );
        decimal::add(position.reserving_fee_amount, delta_fee)
    }

    public fun compute_funding_fee_value<C>(
        position: &Position<C>,
        funding_rate: SRate,
    ): SDecimal {
        let delta_rate = srate::sub(
            funding_rate,
            position.last_funding_rate,
        );
        let delta_fee = sdecimal::from_decimal(
            srate::is_positive(&delta_rate),
            decimal::mul_with_rate(
                position.position_size,
                srate::value(&delta_rate),
            ),
        );
        sdecimal::add(position.funding_fee_value, delta_fee)
    }

    public(friend) fun unwrap_decrease_position_result<Collateral>(res: DecreasePositionResult<Collateral>): (
        bool,
        bool,
        u64,
        u64,
        Decimal,
        Decimal,
        Decimal,
        Decimal,
        SDecimal,
        Coin<Collateral>,
        Coin<Collateral>,
    ) {
        let DecreasePositionResult {
            closed,
            has_profit,
            settled_amount,
            decreased_reserved_amount,
            decrease_size,
            reserving_fee_amount,
            decrease_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        } = res;

        (
            closed,
            has_profit,
            settled_amount,
            decreased_reserved_amount,
            decrease_size,
            reserving_fee_amount,
            decrease_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        )
    }
}
