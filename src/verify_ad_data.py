import pandas as pd
import numpy as np
import os

filepath = r"d:\Data Analyst Portfolio\ecommerce-ad-analytics\data\processed\simulated_ad_spend.csv"

def run_checks():
    print("--- Starting Data Verification ---")
    
    # 1. Check if file exists
    if not os.path.exists(filepath):
        print("[FAIL] File does not exist.")
        return False
    print("[OK] File exists.")
    
    # 2. Load dataset
    df = pd.read_csv(filepath)
    df['date'] = pd.to_datetime(df['date']).dt.date
    
    # 3. Check shape
    expected_rows = 36480 # 608 days * 60 campaigns
    if len(df) != expected_rows:
        print(f"[FAIL] Row count is {len(df)}, expected {expected_rows}.")
        return False
    print(f"[OK] Row count matches expectations ({expected_rows} rows).")
    
    # 4. Check missing values
    missing_counts = df.isnull().sum()
    if missing_counts.sum() > 0:
        print("[FAIL] Found missing values in columns:")
        print(missing_counts[missing_counts > 0])
        return False
    print("[OK] No missing values.")
    
    # 5. Check schema and column types
    expected_cols = [
        "date", "campaign_id", "campaign_name", "channel", 
        "product_category", "product_category_eng", "impressions", 
        "clicks", "ad_spend", "attributed_orders", "attributed_revenue"
    ]
    if list(df.columns) != expected_cols:
        print(f"[FAIL] Column mismatch. Got {list(df.columns)}, expected {expected_cols}.")
        return False
    print("[OK] Column schema is correct.")
    
    # 6. Check date ranges
    min_date = df['date'].min()
    max_date = df['date'].max()
    expected_min = pd.to_datetime("2017-01-01").date()
    expected_max = pd.to_datetime("2018-08-31").date()
    
    if min_date != expected_min or max_date != expected_max:
        print(f"[FAIL] Date range is {min_date} to {max_date}. Expected {expected_min} to {expected_max}.")
        return False
    print(f"[OK] Date range is correct ({min_date} to {max_date}).")
    
    # 7. Check logical integrity of metrics
    # impressions >= clicks
    impr_viol = df[df['impressions'] < df['clicks']]
    if len(impr_viol) > 0:
        print(f"[FAIL] Found {len(impr_viol)} rows where impressions < clicks.")
        return False
        
    # clicks >= attributed_orders
    clicks_viol = df[df['clicks'] < df['attributed_orders']]
    if len(clicks_viol) > 0:
        print(f"[FAIL] Found {len(clicks_viol)} rows where clicks < attributed_orders.")
        return False
        
    # spend >= 0
    spend_viol = df[df['ad_spend'] < 0]
    if len(spend_viol) > 0:
        print(f"[FAIL] Found {len(spend_viol)} rows with negative ad_spend.")
        return False
        
    # orders >= 0
    orders_viol = df[df['attributed_orders'] < 0]
    if len(orders_viol) > 0:
        print(f"[FAIL] Found {len(orders_viol)} rows with negative attributed_orders.")
        return False
        
    # revenue >= 0
    rev_viol = df[df['attributed_revenue'] < 0]
    if len(rev_viol) > 0:
        print(f"[FAIL] Found {len(rev_viol)} rows with negative attributed_revenue.")
        return False
        
    print("[OK] Logical metrics constraints are met (impressions >= clicks >= attributed_orders; spend, orders, revenue >= 0).")
    
    # 8. Spot check specific campaign relationships
    # Check that CTR and CVR distributions are reasonable
    summary = df.groupby('channel').agg(
        total_spend=('ad_spend', 'sum'),
        total_clicks=('clicks', 'sum'),
        total_impressions=('impressions', 'sum'),
        total_orders=('attributed_orders', 'sum'),
        total_rev=('attributed_revenue', 'sum')
    )
    summary['CTR'] = summary['total_clicks'] / summary['total_impressions']
    summary['CVR'] = summary['total_orders'] / summary['total_clicks']
    summary['ROAS'] = summary['total_rev'] / summary['total_spend']
    
    print("\n--- Summary Performance Statistics by Channel ---")
    print(summary)
    
    # Validate channel ROAS logic
    # Display should have lowest ROAS, Retargeting should have highest ROAS
    if summary.loc['Display', 'ROAS'] >= summary.loc['Retargeting', 'ROAS']:
        print("[FAIL] Display ROAS is higher than or equal to Retargeting ROAS. Logic error.")
        return False
    if summary.loc['Display', 'ROAS'] >= 1.0:
        print("[WARN] Display ROAS is >= 1.0, which is unusually high for branding display ads.")
    if summary.loc['Retargeting', 'ROAS'] < 3.0:
        print("[WARN] Retargeting ROAS is < 3.0, which is unusually low for retargeting.")
        
    print("\n[OK] Verification Successful: All test checks passed!")
    return True

if __name__ == "__main__":
    run_checks()
