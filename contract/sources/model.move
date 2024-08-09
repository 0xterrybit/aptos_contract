module perpetual::model {

    use perpetual::rate::{Self, Rate};
    use perpetual::srate::{Self, SRate};
    use perpetual::decimal::{Self, Decimal};
    use perpetual::sdecimal::{Self, SDecimal};

    friend perpetual::market;

    struct RebaseFeeModel has store {
        base: Rate,
        multiplier: Decimal,
    }

    struct ReservingFeeModel has store {
        multiplier: Decimal,
    }

    struct FundingFeeModel has store {
        multiplier: Decimal,
        max: Rate,
    }

    const SECONDS_PER_EIGHT_HOUR: u64 = 28800;

    public(friend) fun create_rebase_fee_model(): RebaseFeeModel {
        RebaseFeeModel {
            base: rate::zero(),
            multiplier: decimal::zero()
        }
    }

    public(friend) fun create_funding_fee_model(multiplier: Decimal, max: Rate): FundingFeeModel {
        FundingFeeModel {
            multiplier,
            max
        }
    }

    public(friend) fun create_reserving_fee_model(multiplier: Decimal): ReservingFeeModel {
        ReservingFeeModel {
            multiplier
        }
    }

    public fun compute_rebase_fee_rate(
        model: &RebaseFeeModel,
        increase: bool,
        ratio: Rate,
        target_ratio: Rate,
    ): Rate {
        if ((increase && rate::le(&ratio, &target_ratio))
            || (!increase && rate::ge(&ratio, &target_ratio))) {
            model.base
        } else {
            let delta_rate = decimal::mul_with_rate(
                model.multiplier,
                rate::diff(ratio, target_ratio),
            );
            rate::add(model.base, decimal::to_rate(delta_rate))
        }
    }

    public fun compute_reserving_fee_rate(
        model: &ReservingFeeModel,
        utilization: Rate,
        elapsed: u64
    ): Rate {
        let daily_rate = decimal::to_rate(
            decimal::mul_with_rate(model.multiplier, utilization)
        );
        rate::div_by_u64(
            rate::mul_with_u64(daily_rate, elapsed),
            SECONDS_PER_EIGHT_HOUR,
        )
    }

    public fun compute_funding_fee_rate(
        model: &FundingFeeModel,
        pnl_per_lp: SDecimal,
        elapsed: u64,
    ): SRate {
        let daily_rate = decimal::to_rate(
            decimal::mul(model.multiplier, sdecimal::value(&pnl_per_lp))
        );
        if (rate::gt(&daily_rate, &model.max)) {
            daily_rate = model.max;
        };
        let seconds_rate = rate::div_by_u64(
            rate::mul_with_u64(daily_rate, elapsed),
            SECONDS_PER_EIGHT_HOUR,
        );
        srate::from_rate(
            !sdecimal::is_positive(&pnl_per_lp),
            seconds_rate,
        )
    }


}
