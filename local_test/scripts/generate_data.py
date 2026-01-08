"""
Generate sample customer and order data as Parquet files

This simulates source data that would come from operational systems.
"""

import random
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path

# Set random seed for reproducibility
np.random.seed(42)
random.seed(42)

FIRST_NAMES = ['John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'Robert', 'Lisa', 'James', 'Mary']
LAST_NAMES = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez']
COUNTRIES = ['AU', 'NZ', 'UK', 'US', 'CA']
SEGMENTS = ['Retail', 'Premium', 'VIP', 'Basic']

EFFECTIVE_TIME_FORMAT = '%Y-%m-%dT%H:%M:%S'
PERIOD_DURATION_DAYS = 7  # each period represents roughly a week


def _generate_phone_numbers(size: int):
    return [f"+61-{np.random.randint(100000000, 999999999)}" for _ in range(size)]


def _base_customer_frame(n_customers=1000):
    customer_ids = [f"CUST-{str(i).zfill(6)}" for i in range(1, n_customers + 1)]

    customers = {
        'customer_id': customer_ids,
        'first_name': np.random.choice(FIRST_NAMES, n_customers),
        'last_name': np.random.choice(LAST_NAMES, n_customers),
        'email': [
            f"{FIRST_NAMES[i % len(FIRST_NAMES)].lower()}.{LAST_NAMES[i % len(LAST_NAMES)].lower()}{i}@example.com"
            for i in range(n_customers)
        ],
        'phone': _generate_phone_numbers(n_customers),
        'country': np.random.choice(COUNTRIES, n_customers),
        'customer_segment': np.random.choice(SEGMENTS, n_customers, p=[0.5, 0.3, 0.1, 0.1]),
        'registration_date': [
            (datetime(2020, 1, 1) + timedelta(days=np.random.randint(0, 1400))).strftime('%Y-%m-%d')
            for _ in range(n_customers)
        ],
        'is_active': np.random.choice([True, False], n_customers, p=[0.9, 0.1]),
    }

    # Introduce some data quality issues (for testing)
    null_indices = np.random.choice(n_customers, size=int(n_customers * 0.01), replace=False)
    for idx in null_indices:
        customers['customer_id'][idx] = None

    null_email_indices = np.random.choice(n_customers, size=int(n_customers * 0.02), replace=False)
    for idx in null_email_indices:
        customers['email'][idx] = None

    return pd.DataFrame(customers)


def _stamp_effective_at(df: pd.DataFrame, base_time: datetime, min_offset=0, max_offset=0):
    if len(df) == 0:
        return df
    if max_offset <= min_offset:
        offsets = [min_offset] * len(df)
    else:
        offsets = np.random.randint(min_offset, max_offset + 1, len(df))
    df['effective_at'] = [
        (base_time + timedelta(minutes=int(offset))).strftime(EFFECTIVE_TIME_FORMAT)
        for offset in offsets
    ]
    return df


def _create_updates(base_df: pd.DataFrame, base_time: datetime, pct: float = 0.1):
    eligible = base_df[base_df['customer_id'].notna()]
    if eligible.empty:
        return pd.DataFrame(columns=base_df.columns)

    update_count = min(max(1, int(len(eligible) * pct)), len(eligible))
    update_idx = np.random.choice(eligible.index, size=update_count, replace=False)
    updates = base_df.loc[update_idx].copy()
    updates['phone'] = _generate_phone_numbers(len(updates))
    updates['country'] = np.random.choice(COUNTRIES, len(updates))
    updates['customer_segment'] = np.random.choice(SEGMENTS, len(updates))
    updates['change_type'] = 'update'
    updates['is_active'] = True
    return _stamp_effective_at(updates, base_time, 10, 120)


def _create_deactivations(base_df: pd.DataFrame, base_time: datetime, pct: float = 0.05):
    eligible = base_df[base_df['customer_id'].notna()]
    if eligible.empty:
        return pd.DataFrame(columns=base_df.columns)

    deactivate_pool = eligible.index
    deactivate_count = min(max(1, int(len(eligible) * pct)), len(eligible))
    deactivate_idx = np.random.choice(deactivate_pool, size=deactivate_count, replace=False)
    deactivations = base_df.loc[deactivate_idx].copy()
    deactivations['is_active'] = False
    deactivations['change_type'] = 'deactivate'
    return _stamp_effective_at(deactivations, base_time, 60, 240)


def _create_new_customers(start_index: int, count: int, base_time: datetime):
    if count <= 0:
        return pd.DataFrame(columns=_base_customer_frame(1).columns)

    new_ids = [f"CUST-{str(i).zfill(6)}" for i in range(start_index, start_index + count)]
    new_df = _base_customer_frame(count)
    new_df['customer_id'] = new_ids
    new_df['change_type'] = 'insert'
    new_df['is_active'] = True
    return _stamp_effective_at(new_df, base_time, 5, 90)


def generate_customer_events(periods=None):
    """
    Return change-log style customer data (inserts, updates, deactivations)
    across multiple weekly periods to simulate attrition.
    """
    if periods is None:
        periods = [
            {'period_days': PERIOD_DURATION_DAYS, 'target_active': 1000, 'new_customers': 0},
            {'period_days': PERIOD_DURATION_DAYS, 'target_active': 500, 'new_customers': 0},
            {'period_days': PERIOD_DURATION_DAYS, 'target_active': 100, 'new_customers': 0},
            {'period_days': PERIOD_DURATION_DAYS * 2, 'target_active': 10, 'new_customers': 0},
        ]

    base_time = datetime.now()
    active_customers = _base_customer_frame(periods[0]['target_active'])
    active_customers['change_type'] = 'insert'
    active_customers = _stamp_effective_at(active_customers, base_time)

    all_events = [active_customers.copy()]
    last_customer_index = periods[0]['target_active']

    for idx, period in enumerate(periods):
        period_start = base_time + timedelta(days=PERIOD_DURATION_DAYS * idx)

        period_updates = _create_updates(active_customers, period_start)
        period_deactivations = _create_deactivations(active_customers, period_start)

        all_events.append(period_updates)
        all_events.append(period_deactivations)

        if len(active_customers) > period['target_active']:
            to_remove = len(active_customers) - period['target_active']
            removal_candidates = active_customers.sample(n=to_remove) if to_remove < len(active_customers) else active_customers
            removal_candidates = removal_candidates.copy()
            removal_candidates['change_type'] = 'deactivate'
            removal_candidates['is_active'] = False
            removal_candidates = _stamp_effective_at(removal_candidates, period_start)
            all_events.append(removal_candidates)
            active_customers = active_customers.drop(removal_candidates.index, errors='ignore')

        add_count = period.get('new_customers', 0)
        if add_count:
            new_customers = _create_new_customers(last_customer_index + 1, add_count, period_start)
            last_customer_index += add_count
            active_customers = pd.concat([active_customers, new_customers], ignore_index=True)
            all_events.append(new_customers)

        active_customers = active_customers.sample(frac=period['target_active'] / len(active_customers), replace=False) if len(active_customers) > period['target_active'] else active_customers

    customer_events = pd.concat(all_events, ignore_index=True)
    active_ids = active_customers[active_customers['customer_id'].notna()]['customer_id'].tolist()

    return customer_events, active_ids


def generate_order_data(n_orders=5000, customer_ids=None):
    """Generate sample order data"""

    if customer_ids is None:
        customer_ids = [f"CUST-{str(i).zfill(6)}" for i in range(1, 1001)]

    # Remove None values from customer_ids
    customer_ids = [cid for cid in customer_ids if cid is not None]

    order_ids = [f"ORD-{str(i).zfill(8)}" for i in range(1, n_orders + 1)]

    statuses = ['completed', 'pending', 'cancelled', 'refunded']

    orders = {
        'order_id': order_ids,
        'customer_id': np.random.choice(customer_ids, n_orders),
        'order_date': [
            (datetime(2023, 1, 1) + timedelta(days=np.random.randint(0, 365))).strftime('%Y-%m-%d')
            for _ in range(n_orders)
        ],
        'order_timestamp': [
            (datetime(2023, 1, 1) + timedelta(days=np.random.randint(0, 365),
                                              hours=np.random.randint(0, 24),
                                              minutes=np.random.randint(0, 60))).isoformat()
            for _ in range(n_orders)
        ],
        'order_status': np.random.choice(statuses, n_orders, p=[0.7, 0.15, 0.1, 0.05]),
        'order_amount': np.round(np.random.uniform(10, 1000, n_orders), 2),
        'currency': 'AUD',
        'payment_method': np.random.choice(['credit_card', 'debit_card', 'bank_transfer', 'paypal'], n_orders),
    }

    # Introduce data quality issues
    # 0.5% negative amounts (data quality test should catch this)
    negative_indices = np.random.choice(n_orders, size=int(n_orders * 0.005), replace=False)
    for idx in negative_indices:
        orders['order_amount'][idx] = -abs(orders['order_amount'][idx])

    # 1% missing order_ids
    null_order_indices = np.random.choice(n_orders, size=int(n_orders * 0.01), replace=False)
    for idx in null_order_indices:
        orders['order_id'][idx] = None

    df = pd.DataFrame(orders)
    return df


def main():
    """Generate and save sample data"""

    # Create output directory
    output_dir = Path(__file__).parent.parent / 'data' / 'decrypted'
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate timestamp for file naming
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

    print("Generating customer data...")
    customers_df, active_customer_ids = generate_customer_events()
    customer_file = output_dir / f'customers_{timestamp}.parquet'
    customers_df.to_parquet(customer_file, engine='pyarrow', compression='snappy')
    print(f"✓ Generated {len(customers_df)} customer change events -> {customer_file}")
    print(f"  - Columns: {list(customers_df.columns)}")
    print(f"  - Change type breakdown: {customers_df['change_type'].value_counts().to_dict()}")
    print(f"  - Sample:\n{customers_df.head(5)}\n")

    print("Generating order data...")
    valid_customer_ids = [cid for cid in active_customer_ids if cid is not None]
    orders_df = generate_order_data(n_orders=5000, customer_ids=valid_customer_ids)
    order_file = output_dir / f'orders_{timestamp}.parquet'
    orders_df.to_parquet(order_file, engine='pyarrow', compression='snappy')
    print(f"✓ Generated {len(orders_df)} orders -> {order_file}")
    print(f"  - Columns: {list(orders_df.columns)}")
    print(f"  - Sample:\n{orders_df.head(3)}\n")

    # Generate summary statistics
    print("=" * 80)
    print("DATA SUMMARY")
    print("=" * 80)
    print(f"\nCustomer events: {len(customers_df)}")
    print(f"  - Inserts: {(customers_df['change_type'] == 'insert').sum()}")
    print(f"  - Updates: {(customers_df['change_type'] == 'update').sum()}")
    print(f"  - Deactivations: {(customers_df['change_type'] == 'deactivate').sum()}")
    print(f"  - Active flag True: {(customers_df['is_active'] == True).sum()}")
    print(f"  - Segments: {customers_df['customer_segment'].value_counts().to_dict()}")
    print(f"  - Countries: {customers_df['country'].value_counts().to_dict()}")
    print(f"  - Data Quality Issues:")
    print(f"    • Missing customer_ids: {customers_df['customer_id'].isna().sum()}")
    print(f"    • Missing emails: {customers_df['email'].isna().sum()}")

    print(f"\nOrders: {len(orders_df)}")
    print(f"  - Total Amount: ${orders_df['order_amount'].sum():,.2f}")
    print(f"  - Avg Order Value: ${orders_df['order_amount'].mean():,.2f}")
    print(f"  - Statuses: {orders_df['order_status'].value_counts().to_dict()}")
    print(f"  - Data Quality Issues:")
    print(f"    • Negative amounts: {(orders_df['order_amount'] < 0).sum()}")
    print(f"    • Missing order_ids: {orders_df['order_id'].isna().sum()}")

    print("\n" + "=" * 80)
    print("FILES READY FOR ENCRYPTION")
    print("=" * 80)
    print(f"Run: python scripts/encrypt_parquet.py {customer_file.name}")
    print(f"Run: python scripts/encrypt_parquet.py {order_file.name}")


if __name__ == '__main__':
    main()
