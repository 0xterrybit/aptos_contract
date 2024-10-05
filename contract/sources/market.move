module perpetual::market {

    use std::signer;
    use std::option;
    use aptos_std::table::{Self, Table};
    use perpetual::rate::{Self, Rate};
    use perpetual::pool::{Self, LONG, SHORT};
    use perpetual::model::{Self, RebaseFeeModel};
    use perpetual::positions::{Self, Position, PositionConfig};
    use perpetual::decimal::{Self, Decimal};
    use perpetual::sdecimal;
    use perpetual::lp;
    use perpetual::admin;
    use perpetual::agg_price;
    use perpetual::referral::{Self, Referral};
    use aptos_std::type_info;
    use perpetual::orders::{Self, OpenPositionOrder, DecreasePositionOrder};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::emit;
    use perpetual::agg_price::AggPrice;

    struct Market has key {
        vaults_locked: bool,
        symbols_locked: bool,

        rebate_model: Rate,
        rebase_model: RebaseFeeModel,
        referrals: Table<address, Referral>
    }

    struct WrappedPositionConfig<phantom Index, phantom Direction> has key {
        enabled: bool,
        inner: PositionConfig
    }

    struct PositionsRecord<phantom CoinType> has key {
        positions: Table<u64, Position<CoinType>>
    }

    struct OrderId<phantom CoinType, phantom Index, phantom Direction, phantom Fee> has store, copy, drop {
        id: u64,
        owner: address,
    }

    struct PositionId<phantom CoinType, phantom Index, phantom Direction> has store, copy, drop {
        id: u64,
        owner: address
    }

    struct PositionRecord<phantom CoinType, phantom Index, phantom Direction> has key {
        creation_num: u64,
        positions: Table<PositionId<CoinType, Index, Direction>, Position<CoinType>>
    }

    struct OrderRecord<phantom CoinType, phantom Index, phantom Direction, phantom Fee> has key {
        creation_num: u64,
        open_orders: Table<OrderId<CoinType, Index, Direction, Fee>, OpenPositionOrder<CoinType, Fee>>,
        decrease_orders: Table<OrderId<CoinType, Index, Direction, Fee>, DecreasePositionOrder<Fee>>
    }

    // === Events ===

    #[event]
    struct MarketCreated has copy, drop, store {
    }

    #[event]
    struct VaultCreated<phantom C> has copy, drop, store {}

    #[event]
    struct SymbolCreated<phantom I, phantom D> has copy, drop, store {}

    #[event]
    struct CollateralAdded<phantom C, phantom I, phantom D> has copy, drop, store {}

    #[event]
    struct CollateralRemoved<phantom C, phantom I, phantom D> has copy, drop, store {}

    #[event]
    struct SymbolStatusUpdated<phantom I, phantom D> has copy, drop, store {
        open_enabled: bool,
        decrease_enabled: bool,
        liquidate_enabled: bool,
    }

    #[event]
    struct PositionConfigReplaced<phantom I, phantom D> has copy, drop, store {
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128,
    }

    #[event]
    struct RebateRateUpdated has copy, drop, store {
        rebate_rate: Rate,
    }

    #[event]
    struct ReferralAdded has copy, drop, store {
        referrer: address,
        rebate_rate: Rate,
    }

    #[event]
    struct PositionClaimed<phantom Collateral, phantom Index, phantom Direction> has copy, drop, store {
    }

    #[event]
    struct Deposited<phantom C> has copy, drop, store {
        minter: address,
        // price: Decimal,
        deposit_amount: u64,
        mint_amount: u64,
        fee_value: Decimal,
    }

    #[event]
    struct Withdrawn<phantom C> has copy, drop, store {
        burner: address,
        // price: Decimal,
        withdraw_amount: u64,
        burn_amount: u64,
        fee_value: Decimal,
    }

    #[event]
    struct Swapped<phantom S, phantom D> has copy, drop, store {
        swapper: address,
        // source_price: Decimal,
        // dest_price: Decimal,
        source_amount: u64,
        dest_amount: u64,
        fee_value: Decimal,
    }

    #[event]
    struct OrderCreated<phantom Collateral, phantom Index, phantom Direction> has copy, drop, store {
        user_account: address
    }

    #[event]
    struct OrderExecuted<phantom Collateral, phantom Index, phantom Direction> has copy, drop, store {
        executor: address,
    }

    #[event]
    struct OrderCleared<phantom Collateral, phantom Index, phantom Direction> has copy, drop, store {
    }

    #[event]
    struct VaultInfo has drop {
        price: AggPrice,
        value: Decimal,
    }

    // === Errors ===
    // common errors
    const ERR_FUNCTION_VERSION_EXPIRED: u64 = 1;
    const ERR_MARKET_ALREADY_LOCKED: u64 = 2;
    // referral errors
    const ERR_ALREADY_HAS_REFERRAL: u64 = 3;
    // perpetual trading errors
    const ERR_INVALID_DIRECTION: u64 = 4;
    const ERR_CAN_NOT_CREATE_ORDER: u64 = 5;
    const ERR_CAN_NOT_TRADE_IMMEDIATELY: u64 = 6;
    // deposit, withdraw and swap errors
    const ERR_VAULT_ALREADY_HANDLED: u64 = 7;
    const ERR_SYMBOL_ALREADY_HANDLED: u64 = 8;
    const ERR_VAULTS_NOT_TOTALLY_HANDLED: u64 = 9;
    const ERR_SYMBOLS_NOT_TOTALLY_HANDLED: u64 = 10;
    const ERR_UNEXPECTED_MARKET_VALUE: u64 = 11;
    const ERR_MISMATCHED_RESERVING_FEE_MODEL: u64 = 12;
    const ERR_SWAPPING_SAME_COINS: u64 = 13;

    fun init_module (
        admin: &signer,
    ) {
        // create rebase fee model
        let rebase_rate = model::create_rebase_fee_model();

        //TODO: assign rebate rate here
        let rebate_rate = rate::zero();
        // move market resource to account
        let market = Market {
            vaults_locked: false,
            symbols_locked: false,

            rebate_model: rebate_rate,
            rebase_model: rebase_rate,
            referrals: table::new<address, Referral>()

        };
        move_to(admin, market);

        // https://github.com/aptos-labs/aptos-core/issues/11038
        // emit(MarketCreated{});
    }

    public entry fun add_new_vault<Collateral>(
        admin: &signer,
        weight: u256,
        max_interval: u64,
        max_price_confidence: u64,
        feeder: vector<u8>,
        param_multiplier: u256,
    ) {

        admin::check_permission(signer::address_of(admin));
        let identifier = pyth::price_identifier::from_byte_vec(feeder);

        // create reserving fee model
        let model = model::create_reserving_fee_model(
            decimal::from_raw(param_multiplier));

        // add vault to market
        pool::new_vault<Collateral>(
            admin,
            weight,
            model,
            agg_price::new_agg_price_config<Collateral>(
                max_interval,
                max_price_confidence,
                identifier
            )
        );

        emit(VaultCreated<Collateral>{})
    }


    public entry fun add_new_referral<L>(referrer: &signer) acquires Market {
        
        let market = borrow_global_mut<Market>(@perpetual);

        assert!(
            !table::contains(&market.referrals, referrer),
            ERR_ALREADY_HAS_REFERRAL,
        );

        let referral = referral::new_referral(referrer, market.rebate_model);

        
        table::add(&mut market.referrals, referrer, referral);

        emit(ReferralAdded {
            referrer,
            rebate_rate: market.rebate_model,
        });
    }

    public entry fun replace_vault_feeder<Collateral>(
        admin: &signer,
        feeder: vector<u8>,
        max_interval: u64,
        max_price_confidence: u64
    ) {
        admin::check_permission(signer::address_of(admin));
        let identifier = pyth::price_identifier::from_byte_vec(feeder);
        let price_config =
            agg_price::new_agg_price_config<Collateral>(max_interval, max_price_confidence, identifier);
        pool::replace_vault_price_config<Collateral>(admin, price_config);
    }

    public entry fun add_new_symbol<Index, Direction>(
        admin: &signer,
        max_interval: u64,
        max_price_confidence: u64,
        feeder: vector<u8>,
        param_multiplier: u256,
        param_max: u128,
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128
    ) {
        admin::check_permission(signer::address_of(admin));
        // create funding fee model
        let model = model::create_funding_fee_model(
            decimal::from_raw(param_multiplier),
            rate::from_raw(param_max)
        );
        // create public position config
        move_to(admin, WrappedPositionConfig<Index, Direction>{
            enabled: true,
            inner: positions::new_position_config(
                max_leverage,
                min_holding_duration,
                max_reserved_multiplier,
                min_collateral_value,
                open_fee_bps,
                decrease_fee_bps,
                liquidation_threshold,
                liquidation_bonus
            )
        });
        let identifier = pyth::price_identifier::from_byte_vec(feeder);
        // add symbol to market
        pool::new_symbol<Index, Direction>(admin, model, agg_price::new_agg_price_config<Index>(
            max_interval,
            max_price_confidence,
            identifier
        ));
        emit(SymbolCreated<Index, Direction>{});
    }

    public entry fun replace_symbol_feeder<Index, Direction>(
        admin: &signer,
        feeder: vector<u8>,
        max_interval: u64,
        max_price_confidence: u64
    ) {
        admin::check_permission(signer::address_of(admin));
        let identifier = pyth::price_identifier::from_byte_vec(feeder);
        let price_config = agg_price::new_agg_price_config<Index>(max_interval, max_price_confidence, identifier);
        pool::replace_symbol_price_config<Index, Direction>(admin, price_config);
        // TODO: emit event
    }

    public entry fun add_collateral_to_symbol<Collateral, Index, Direction>(
        admin: &signer
    ) {
        admin::check_permission(signer::address_of(admin));
        // pool::add_collateral_to_symbol
        pool::add_collateral_to_symbol<Index, Direction, Collateral>(admin);
        // create record
        if (!exists<PositionRecord<Collateral, Index, Direction>>(@perpetual)){
            move_to(admin, PositionRecord<Collateral, Index, Direction>{
                creation_num: 0,
                positions: table::new<PositionId<Collateral, Index, Direction>, Position<Collateral>>()
            })
        };

        if (!exists<OrderRecord<Collateral, Index, Direction, AptosCoin>>(@perpetual)) {
            move_to(admin, OrderRecord<Collateral, Index, Direction, AptosCoin>{
                creation_num: 0,
                open_orders: table::new<OrderId<Collateral, Index, Direction, AptosCoin>, OpenPositionOrder<Collateral, AptosCoin>>(),
                decrease_orders: table::new<OrderId<Collateral, Index, Direction, AptosCoin>, DecreasePositionOrder<AptosCoin>>()
            })
        };
        emit(CollateralAdded<Collateral, Index, Direction>{});
    }

    public entry fun remove_collateral_from_symbol<Collateral, Index, Direction>(
        admin: &signer
    ) {
        admin::check_permission(signer::address_of(admin));
        // pool::remove_collateral_to_symbol
        pool::remove_collateral_to_symbol<Collateral, Index, Direction>(admin);
    }

    public entry fun set_symbol_status<Index, Direction>(
        admin: &signer,
        open_enabled: bool,
        decrease_enabled: bool,
        liquidate_enabled: bool
    ) {
        admin::check_permission(signer::address_of(admin));
        pool::set_symbol_status<Index, Direction>(admin, open_enabled, decrease_enabled, liquidate_enabled);
        emit(SymbolStatusUpdated<Index, Direction>{
            open_enabled,
            decrease_enabled,
            liquidate_enabled
        });
    }

    public entry fun replace_position_config<Index, Direction>(
        admin: &signer,
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128,
    ) acquires WrappedPositionConfig {
        admin::check_permission(signer::address_of(admin));
        let wrapped_position_config =
            borrow_global_mut<WrappedPositionConfig<Index, Direction>>(signer::address_of(admin));
        let new_positions_config = positions::new_position_config(
                max_leverage,
                min_holding_duration,
                max_reserved_multiplier,
                min_collateral_value,
                open_fee_bps,
                decrease_fee_bps,
                liquidation_threshold,
                liquidation_bonus
            );
        wrapped_position_config.inner = new_positions_config;
        emit(PositionConfigReplaced<Index, Direction>{
            max_leverage,
            min_holding_duration,
            max_reserved_multiplier,
            min_collateral_value,
            open_fee_bps,
            decrease_fee_bps,
            liquidation_threshold,
            liquidation_bonus,
        });
    }

    public entry fun open_position<Collateral, Index, Direction, Fee>(
        user: &signer,
        trade_level: u8,
        open_amount: u64,
        reserve_amount: u64,
        collateral_amount: u64,
        fee_amount: u64,
        collateral_price_threshold: u256,
        limited_index_price: u256,
        vaas: vector<vector<u8>>
    ) acquires Market, WrappedPositionConfig, OrderRecord, PositionRecord {
        let user_account = signer::address_of(user);
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);
        let lp_supply_amount = lp_supply_amount();
        let timestamp = timestamp::now_seconds();
        let long = parse_direction<Direction>();

        let collateral_price_threshold = decimal::from_raw(collateral_price_threshold);
        let index_price = agg_price::parse_pyth_feeder(
            &pool::symbol_price_config<Index, Direction>(),
            timestamp
        );
        let limited_index_price = agg_price::from_price(
            &pool::symbol_price_config<Index, Direction>(),
            decimal::from_raw(limited_index_price),
        );

        // check if limited order can be placed
        let placed = if (long) {
            decimal::gt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        } else {
            decimal::lt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        };

        let position_config =
            borrow_global<WrappedPositionConfig<Index, Direction>>(@perpetual);

        if (placed) {
            assert!(trade_level < 2, ERR_CAN_NOT_CREATE_ORDER);
            let order = orders::new_open_position_order<Collateral, Fee>(
                timestamp,
                open_amount,
                reserve_amount,
                limited_index_price,
                collateral_price_threshold,
                position_config.inner,
                coin::withdraw<Collateral>(user, collateral_amount),
                coin::withdraw<Fee>(user, fee_amount)
            );
            // add order into record
            let order_record =
                borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
            table::add(&mut order_record.open_orders, OrderId<Collateral, Index, Direction, Fee>{
                id: order_record.creation_num,
                owner: user_account
            }, order);
            order_record.creation_num = order_record.creation_num + 1;
            emit(OrderCreated<Collateral, Index, Direction>{
                user_account
            });

        } else {
            let (rebate_rate, referrer) = get_referral_data(&market.referrals, user_account);
            let (code, collateral, result, _) = pool::open_position<Collateral, Index, Direction>(
                &position_config.inner,
                coin::withdraw<Collateral>(user, collateral_amount),
                collateral_price_threshold,
                rebate_rate,
                long,
                open_amount,
                reserve_amount,
                lp_supply_amount,
                timestamp,
            );
            coin::deposit(user_account, collateral);
            // should panic when the owner execute the order
            assert!(code == 0, code);
            //coin::destroy_zero(collateral);

            let (position, rebate, _event) =
                pool::unwrap_open_position_result<Collateral>(option::destroy_some(result));

            // add position into record
            let position_record =
                borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
            table::add(&mut position_record.positions, PositionId<Collateral, Index, Direction>{
                id: position_record.creation_num,
                owner: user_account
            }, position);
            position_record.creation_num = position_record.creation_num + 1;

            if (referrer != @0x0) {
                coin::deposit(referrer, rebate);
            } else {
                coin::deposit(user_account, rebate);
            };

            emit(OrderExecuted<Collateral, Index, Direction>{
                executor: user_account
            });
        }
    }

    public entry fun decrease_position<Collateral, Index, Direction, Fee>(
        user: &signer,
        trade_level: u8,
        fee_amount: u64,
        take_profit: bool,
        decrease_amount: u64,
        collateral_price_threshold: u256,
        limited_index_price: u256,
        position_num: u64,
        vaas: vector<vector<u8>>
    ) acquires Market, PositionRecord, OrderRecord {
        let user_account = signer::address_of(user);
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);
        let lp_supply_amount = lp_supply_amount();
        let timestamp = timestamp::now_seconds();
        let long = parse_direction<Direction>();

        let collateral_price_threshold = decimal::from_raw(collateral_price_threshold);
        let index_price = agg_price::parse_pyth_feeder(
            &pool::symbol_price_config<Index, Direction>(),
            timestamp
        );
        let limited_index_price = agg_price::from_price(
            &pool::symbol_price_config<Index, Direction>(),
            decimal::from_raw(limited_index_price),
        );
        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner: user_account
        };

        // check if limit order can be placed
        let placed = if (long) {
            decimal::lt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        } else {
            decimal::gt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        };

        // Decrease order is allowed to create:
        // 1: limit order can be placed
        // 2: limit order can not placed, but it must be a stop loss order
        if (placed || !take_profit) {
            assert!(trade_level < 2, ERR_CAN_NOT_CREATE_ORDER);

            let order = orders::new_decrease_position_order(
                timestamp,
                take_profit,
                decrease_amount,
                limited_index_price,
                collateral_price_threshold,
                coin::withdraw<Fee>(user, fee_amount),
            );
            // add order into record
            let order_record = borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
            table::add(&mut order_record.decrease_orders, OrderId<Collateral, Index, Direction, Fee>{
                id: order_record.creation_num,
                owner: user_account
            }, order);
            order_record.creation_num = order_record.creation_num + 1;

            emit(OrderCreated<Collateral, Index, Direction> { user_account });
        } else {
            assert!(trade_level > 0, ERR_CAN_NOT_TRADE_IMMEDIATELY);

            let position_record = borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
            let position  = table::borrow_mut(
                &mut position_record.positions,
                position_id
            );

            let (rebate_rate, referrer) = get_referral_data(&market.referrals, user_account);
            let (code, result, _) = pool::decrease_position<Collateral, Index, Direction>(
                position,
                collateral_price_threshold,
                rebate_rate,
                long,
                decrease_amount,
                lp_supply_amount,
                timestamp,
            );

            // should panic when the owner execute the order
            assert!(code == 0, code);

            let res = option::destroy_some(result);
            let (to_trader, rebate, _event) = pool::unwrap_decrease_position_result<Collateral>(res);

            coin::deposit<Collateral>(user_account, to_trader);
            coin::deposit<Collateral>(referrer, rebate);
            
            emit(PositionClaimed<Collateral, Index, Direction> {});
        }
    }

    public entry fun decrease_reserved_from_position<Collateral, Index, Direction>(
        user: &signer,
        decrease_amount: u64,
        position_num: u64,
        vaas: vector<vector<u8>>
    ) acquires PositionRecord {
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        let timestamp = timestamp::now_seconds();
        let user_account = signer::address_of(user);

        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner: user_account,
        };

        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::borrow_mut(
            &mut position_record.positions,
            position_id
        );

        let _event = pool::decrease_reserved_from_position(
            position,
            decrease_amount,
            timestamp
        );

        emit(PositionClaimed<Collateral, Index, Direction> {});
    }

    public entry fun pledge_in_position<Collateral, Index, Direction>(
        user: &signer,
        pledge_num: u64,
        position_num: u64,
    ) acquires PositionRecord  {
        let user_account = signer::address_of(user);

        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner: user_account
        };
        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::borrow_mut(
            &mut position_record.positions,
            position_id
        );

        let _event = pool::pledge_in_position(position, coin::withdraw<Collateral>(user, pledge_num));

        emit(PositionClaimed<Collateral, Index, Direction> {});
    }

    public entry fun redeem_from_position<Collateral, Index, Direction>(
        user: &signer,
        redeem_amount: u64,
        position_num: u64,
        vaas: vector<vector<u8>>
    ) acquires Market, PositionRecord {
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);


        let timestamp = timestamp::now_seconds();
        let user_account = signer::address_of(user);
        let lp_supply_amount = lp_supply_amount();
        let long = parse_direction<Direction>();

        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner: user_account,
        };
        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::borrow_mut(
            &mut position_record.positions,
            position_id
        );

        let (redeem, _event) = pool::redeem_from_position<Collateral, Index, Direction>(
            position,
            long,
            redeem_amount,
            lp_supply_amount,
            timestamp,
        );

        coin::deposit(user_account, redeem);

        emit(PositionClaimed<Collateral, Index, Direction> {});

    }

    public entry fun liquidate_position<Collateral, Index, Direction>(
        liquidator: &signer,
        owner: address,
        position_num: u64,
        vaas: vector<vector<u8>>
    ) acquires Market, PositionRecord {
        pyth::pyth::update_price_feeds_with_funder(liquidator, vaas);
        let liquidator_account = signer::address_of(liquidator);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);


        let timestamp = timestamp::now_seconds();
        let lp_supply_amount = lp_supply_amount();
        let long = parse_direction<Direction>();

        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner,
        };
        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::borrow_mut(
            &mut position_record.positions,
            position_id
        );

        let (liquidation_fee, _event) = pool::liquidate_position<Collateral, Index, Direction>(
            position,
            long,
            lp_supply_amount,
            timestamp,
            liquidator_account,
        );

        coin::deposit(liquidator_account, liquidation_fee);

        emit(PositionClaimed<Collateral, Index, Direction> {});

    }

    public entry fun clear_closed_position<Collateral, Index, Direction>(
        user: &signer,
        position_num: u64
    ) acquires Market, PositionRecord {
        let user_account = signer::address_of(user);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner: user_account,
        };
        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::remove(
            &mut position_record.positions,
            position_id
        );

        positions::destroy_position<Collateral>(position);
    }

    public entry fun execute_open_position_order<Collateral, Index, Direction, Fee>(
        executor: &signer,
        owner: address,
        order_num: u64,
        vaas: vector<vector<u8>>
    ) acquires Market, PositionRecord, OrderRecord {
        pyth::pyth::update_price_feeds_with_funder(executor, vaas);
        let executor_account = signer::address_of(executor);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = timestamp::now_seconds();
        let lp_supply_amount = lp_supply_amount();
        let long = parse_direction<Direction>();

        let order_id = OrderId<Collateral, Index, Direction, Fee> {
            id: order_num,
            owner,
        };
        let order_record =
            borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
        let order = table::borrow_mut(&mut order_record.open_orders, order_id);

        let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
        let (
            code, collateral,
            result,
            failure,
            fee
        ) = orders::execute_open_position_order<Collateral, Index, Direction, Fee>(
            order,
            rebate_rate,
            long,
            lp_supply_amount,
            timestamp,
        );
        if (code == 0) {
            let (position, rebate, _event) =
                pool::unwrap_open_position_result(option::destroy_some(result));

            let position_record =
                borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
            let position_id = PositionId<Collateral, Index, Direction> {
                id: position_record.creation_num,
                owner: order_id.owner,
            };
            table::add(
                &mut position_record.positions,
                position_id,
                position
            );
            position_record.creation_num = position_record.creation_num + 1;

            if (referrer == @0x0) {
                coin::deposit(executor_account, rebate);
            } else {
                coin::deposit(referrer, rebate);
            };

            emit(OrderExecuted<Collateral, Index, Direction> { executor: executor_account });
        } else {
            // executed order failed

            option::destroy_none(result);
            let _event = option::destroy_some(failure);
            //TODO: maybe should panic here directly?
            assert!(code == 0, code);
            // emit order executed and open failed
            // event::emit(OrderExecuted {
            //     executor,
            //     order_name,
            //     claim: PositionClaimed {
            //         position_name: option::none<PositionName<C, I, D>>(),
            //         event,
            //     },
            // });
        };
        // TODO: check currency here
        coin::destroy_zero(collateral);
        coin::deposit(executor_account, fee);
    }

    public entry fun execute_decrease_position_order<Collateral, Index, Direction, Fee>(
        executor: &signer,
        owner: address,
        order_num: u64,
        position_num: u64,
        vaas: vector<vector<u8>>
    ) acquires Market, OrderRecord, PositionRecord {
        pyth::pyth::update_price_feeds_with_funder(executor, vaas);
        let executor_account = signer::address_of(executor);
        let market = borrow_global_mut<Market>(@perpetual);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = timestamp::now_seconds();
        let lp_supply_amount = lp_supply_amount();
        let long = parse_direction<Direction>();

        let order_id = OrderId<Collateral, Index, Direction, Fee> {
            id: order_num,
            owner,
        };
        let order_record =
            borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
        let order = table::borrow_mut(&mut order_record.decrease_orders, order_id);

        let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
        let position_id = PositionId<Collateral, Index, Direction> {
            id: position_num,
            owner,
        };
        let position_record =
            borrow_global_mut<PositionRecord<Collateral, Index, Direction>>(@perpetual);
        let position  = table::borrow_mut(
            &mut position_record.positions,
            position_id
        );
        let (code, result, failure, fee) =
            orders::execute_decrease_position_order<Collateral, Index, Direction, Fee>(
                order,
                position,
                rebate_rate,
                long,
                lp_supply_amount,
                timestamp,
        );
        if (code == 0) {
            let (to_trader, rebate, _event) =
                pool::unwrap_decrease_position_result(option::destroy_some(result));

            coin::deposit(owner, to_trader);
            coin::deposit(referrer, rebate);

            emit(OrderExecuted<Collateral, Index, Direction> { executor: executor_account });
        } else {
            // executed order failed
            option::destroy_none(result);
            let _event = option::destroy_some(failure);

            //TODO: assert! maybe abort directly?

            emit(OrderExecuted<Collateral, Index, Direction> { executor: executor_account });
        };

        coin::deposit(executor_account, fee);

    }

    public entry fun clear_open_position_order<Collateral, Index, Direction, Fee>(
        user: &signer,
        order_num: u64,
    ) acquires OrderRecord {
        let user_account = signer::address_of(user);

        let order_id = OrderId<Collateral, Index, Direction, Fee> {
            id: order_num,
            owner: user_account
        };
        let order_record =
            borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
        let order = table::remove(&mut order_record.open_orders, order_id);
        let (collateral, fee) = orders::destroy_open_position_order(order);

        emit(OrderCleared<Collateral, Index, Direction> { });

        coin::deposit(user_account, collateral);
        coin::deposit(user_account, fee);
    }

    public entry fun clear_decrease_position_order<Collateral, Index, Direction, Fee>(
        user: &signer,
        order_num: u64
    ) acquires OrderRecord {
        let user_account = signer::address_of(user);

        let order_id = OrderId<Collateral, Index, Direction, Fee> {
            id: order_num,
            owner: user_account
        };
        let order_record =
            borrow_global_mut<OrderRecord<Collateral, Index, Direction, Fee>>(@perpetual);
        let order = table::remove(&mut order_record.decrease_orders, order_id);
        let fee = orders::destory_decrease_position_order(order);

        emit(OrderCleared<Collateral, Index, Direction> { });

        coin::deposit(user_account, fee);

    }

    public entry fun deposit<Collateral>(
        user: &signer,
        deposit_amount: u64,
        min_amount_out: u64,
        vaas: vector<vector<u8>>
    ) acquires Market {
        
        
        pyth::pyth::update_price_feeds_with_funder(user, vaas);

        
        let market = borrow_global_mut<Market>(@perpetual);

        let (
            total_weight,
            total_vaults_value,
            market_value,
        ) = finalize_market_valuation();

        let vault_value = pool::vault_value<Collateral>(timestamp::now_seconds());

        let (mint_amount, fee_value) = pool::deposit<Collateral>(
            user,
            &market.rebase_model,
            deposit_amount,
            min_amount_out,
            market_value,
            vault_value,
            total_vaults_value,
            total_weight,
        );

        // mint to sender
        lp::mint_to(user, mint_amount);

        emit(Deposited<Collateral> {
            minter: signer::address_of(user),
            // price: agg_price::price_of(&price),
            deposit_amount,
            mint_amount,
            fee_value,
        });
    }

    public entry fun withdraw<Collateral>(
        user: &signer,
        lp_burn_amount: u64,
        min_amount_out: u64,
        vaas: vector<vector<u8>>
    ) acquires Market {
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        let market = borrow_global_mut<Market>(@perpetual);
        let (
            total_weight,
            total_vaults_value,
            market_value,
        ) = finalize_market_valuation();

        let vault_value = pool::vault_value<Collateral>(timestamp::now_seconds());

        // withdraw to burner
        let (withdraw, fee_value) = pool::withdraw<Collateral>(
            &market.rebase_model,
            lp_burn_amount,
            min_amount_out,
            market_value,
            vault_value,
            total_vaults_value,
            total_weight,
        );
        let withdraw_amount = coin::value(&withdraw);
        // burn lp
        lp::burn(user, lp_burn_amount);

        coin::deposit(signer::address_of(user), withdraw);

        emit(Withdrawn<Collateral> {
            burner: signer::address_of(user),
            // price: agg_price::price_of(&price),
            withdraw_amount,
            burn_amount: lp_burn_amount,
            fee_value,
        });

    }

    #[view]
    public fun calculate_swap_fee<Source, Destination>(): (Rate, Rate) acquires Market {
        
        // borrow market and valuate market
        let market = borrow_global_mut<Market>(@perpetual);
        let (
            total_weight,
            total_vaults_value,
            _market_value,
        ) = finalize_market_valuation();

        // timestamp
        let timestamp = timestamp::now_seconds();

        // vault value
        let source_vault_value = pool::vault_value<Source>(timestamp);
        let dest_vault_value = pool::vault_value<Destination>(timestamp);

        let swap_in_rate = pool::possible_swap_fee_rate<Source>(
            &market.rebase_model,
            true,
            source_vault_value,
            total_vaults_value,
            total_weight
        );

        let swap_out_rate = pool::possible_swap_fee_rate<Destination>(
            &market.rebase_model,
            false,
            dest_vault_value,
            total_vaults_value,
            total_weight
        );
        
        (swap_in_rate, swap_out_rate)
    }


    public entry fun swap<Source, Destination>(
        user: &signer,
        amount_in: u64,
        min_amount_out: u64,
        vaas: vector<vector<u8>>
    ) acquires Market {
        pyth::pyth::update_price_feeds_with_funder(user, vaas);
        assert!(
            type_info::type_name<Source>() != type_info::type_name<Destination>(),
            ERR_SWAPPING_SAME_COINS,
        );
        let user_account = signer::address_of(user);
        let market = borrow_global_mut<Market>(@perpetual);
        let (
            total_weight,
            total_vaults_value,
            _market_value,
        ) = finalize_market_valuation();
        let source_vault_value = pool::vault_value<Source>(timestamp::now_seconds());
        let destination_vault_value = pool::vault_value<Destination>(timestamp::now_seconds());

        // swap step 1
        let (swap_value, source_fee_value) = pool::swap_in<Source>(
            &market.rebase_model,
            coin::withdraw<Source>(user, amount_in),
            source_vault_value,
            total_vaults_value,
            total_weight,
        );

        // swap step 2
        let (receiving, dest_fee_value) = pool::swap_out<Destination>(
            &market.rebase_model,
            min_amount_out,
            swap_value,
            destination_vault_value,
            total_vaults_value,
            total_weight,
        );
        let dest_amount = coin::value(&receiving);

        coin::deposit(user_account, receiving);

        emit(Swapped<Source, Destination> {
            swapper: user_account,
            // source_price: agg_price::price_of(&source_price),
            // dest_price: agg_price::price_of(&dest_price),
            source_amount: amount_in,
            dest_amount,
            fee_value: decimal::add(source_fee_value, dest_fee_value),
        });

    }

    fun finalize_market_valuation(): (Decimal, Decimal, Decimal) {
        
        let (vault_total_value, vault_total_weight) = pool::vault_valuation();

        let symbol_total_value = pool::symbol_valuation();

        let market_value = sdecimal::add_with_decimal(symbol_total_value, vault_total_value);
        
        (vault_total_weight, vault_total_value, sdecimal::value(&market_value))
    }

    #[view]
    public fun to_lp_amount<Collateral>(deposit_amount: u64): u64 {
        let (_, _, market_value) = finalize_market_valuation();
        let deposit_value_decimal = pool::collateral_value<Collateral>(deposit_amount);
        let lp_supply_amount = pool::lp_supply_amount();
        let exchange_rate = decimal::to_rate(
            decimal::div(deposit_value_decimal, market_value)
        );
        decimal::floor_u64(
            decimal::mul_with_rate(
                lp_supply_amount,
                exchange_rate,
            )
        )
    }

    #[view]
    public fun to_collateral_amount<Collateral>(lp_burn_amount: u64): u64 {
        let (_, _, market_value) = finalize_market_valuation();
        let exchange_rate = decimal::to_rate(
            decimal::div(
                decimal::from_u64(lp_burn_amount),
                pool::lp_supply_amount(),
            )
        );
        let withdraw_value = decimal::mul_with_rate(market_value, exchange_rate);
        pool::collateral_amount<Collateral>(withdraw_value)
    }

    public fun force_close_position<Collateral, Index, Direction>() {}

    public fun force_clear_closed_position<Collateral, Index, Direction>() {}

    public fun lp_supply_amount(): Decimal {
        // LP decimal is 6
        let supply = lp::get_supply();
        decimal::div_by_u64(
            decimal::from_u128(supply),
            1_000_000,
        )
    }

    public fun parse_direction<Direction>(): bool {
        let direction = type_info::type_of<Direction>();
        if (direction == type_info::type_of<LONG>()) {
            true
        } else {
            assert!(
                direction == type_info::type_of<SHORT>(),
                ERR_INVALID_DIRECTION,
            );
            false
        }
    }

    fun get_referral_data(
        referrals: &Table<address, Referral>,
        owner: address
    ): (Rate, address) {

        if (table::contains(referrals, owner)) {
            let referral = table::borrow(referrals, owner);

            (
                referral::get_rebate_rate(referral), 
                referral::get_referrer(referral)
            )


        } else {
            (rate::zero(), @0x0)
        }
    }


}
#[test_only]
module perpetual::pool_tests {
    use perpetual::market;

    #[test]
    fun test_add() {
       
        
    }

}
