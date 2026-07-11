import pandas as pd
import numpy as np
import os
from datetime import datetime

# Set seed for reproducibility
np.random.seed(42)

# File paths
raw_dir = r"d:\Data Analyst Portfolio\ecommerce-ad-analytics\data\raw"
output_path = r"d:\Data Analyst Portfolio\ecommerce-ad-analytics\data\processed\simulated_ad_spend.csv"

# Create output directory if it doesn't exist
os.makedirs(os.path.dirname(output_path), exist_ok=True)

print("Loading Olist data...")
orders = pd.read_csv(os.path.join(raw_dir, "olist_orders_dataset.csv"))
items = pd.read_csv(os.path.join(raw_dir, "olist_order_items_dataset.csv"))
products = pd.read_csv(os.path.join(raw_dir, "olist_products_dataset.csv"))

# Parse order timestamps and extract date
print("Processing dates and filtering orders...")
orders['order_purchase_timestamp'] = pd.to_datetime(orders['order_purchase_timestamp'])
orders['date'] = orders['order_purchase_timestamp'].dt.date

# Filter for active period (2017-01-01 to 2018-08-31) and exclude canceled/unavailable orders
start_date = datetime(2017, 1, 1).date()
end_date = datetime(2018, 8, 31).date()

valid_orders = orders[
    (orders['date'] >= start_date) & 
    (orders['date'] <= end_date) & 
    (~orders['order_status'].isin(['canceled', 'unavailable']))
]

# Merge items and products to get category
merged_items = items.merge(products[['product_id', 'product_category_name']], on='product_id', how='left')
# Fill missing categories with 'other'
merged_items['product_category_name'] = merged_items['product_category_name'].fillna('outro')

# Merge with orders to get date
sales_data = merged_items.merge(valid_orders[['order_id', 'date']], on='order_id', how='inner')

# Calculate daily sales by category
print("Aggregating daily sales per category...")
daily_sales = sales_data.groupby(['date', 'product_category_name']).agg(
    actual_orders=('order_id', 'nunique'),
    actual_revenue=('price', 'sum')
).reset_index().rename(columns={'product_category_name': 'product_category'})

# Top 15 categories by total items sold in Olist
top_categories = [
    "cama_mesa_banho", "beleza_saude", "esporte_lazer", "moveis_decoracao",
    "informatica_acessorios", "utilidades_domesticas", "relogios_presentes",
    "telefonia", "ferramentas_jardim", "automotivo", "brinquedos",
    "cool_stuff", "perfumaria", "bebes", "eletronicos"
]

category_translation = {
    "cama_mesa_banho": "Bed_Bath_Table",
    "beleza_saude": "Health_Beauty",
    "esporte_lazer": "Sports_Leisure",
    "moveis_decoracao": "Furniture_Decor",
    "informatica_acessorios": "Computers_Accessories",
    "utilidades_domesticas": "Housewares",
    "relogios_presentes": "Watches_Gifts",
    "telefonia": "Telephony",
    "ferramentas_jardim": "Garden_Tools",
    "automotivo": "Automotive",
    "brinquedos": "Toys",
    "cool_stuff": "Cool_Stuff",
    "perfumaria": "Perfumery",
    "bebes": "Baby",
    "eletronicos": "Electronics"
}

# Create campaign configurations
print("Configuring campaigns...")
campaigns = []
id_counter = 1
for cat in top_categories:
    cat_eng = category_translation[cat]
    for channel in ["Google", "Meta", "Display", "Retargeting"]:
        camp_id = f"CAMP_{id_counter:03d}"
        camp_name = f"{channel}_{cat_eng}_Acquisition" if channel != "Retargeting" else f"{channel}_{cat_eng}_Remarketing"
        campaigns.append({
            "campaign_id": camp_id,
            "campaign_name": camp_name,
            "channel": channel,
            "product_category": cat,
            "product_category_eng": cat_eng
        })
        id_counter += 1

campaigns_df = pd.DataFrame(campaigns)

# Create a complete grid of date x campaign
print("Generating date-campaign grid...")
dates = pd.date_range(start_date, end_date).date
grid_list = []
for d in dates:
    for camp in campaigns:
        grid_list.append({
            "date": d,
            "campaign_id": camp["campaign_id"],
            "campaign_name": camp["campaign_name"],
            "channel": camp["channel"],
            "product_category": camp["product_category"],
            "product_category_eng": camp["product_category_eng"]
        })
grid_df = pd.DataFrame(grid_list)

# Merge grid with daily sales
print("Merging sales data with campaigns...")
full_df = grid_df.merge(daily_sales, on=['date', 'product_category'], how='left')
full_df['actual_orders'] = full_df['actual_orders'].fillna(0).astype(int)
full_df['actual_revenue'] = full_df['actual_revenue'].fillna(0.0)

# Define Channel parameters (Mean, Std)
# attribution_rate: portion of category sales driven by this channel
# ctr: Click-Through Rate
# cvr: Conversion Rate (clicks to orders)
# cpc: Cost-Per-Click (for Google, Meta, Retargeting)
# cpm: Cost-Per-Thousand-Impressions (for Display)
# base_clicks: baseline clicks when there are zero sales
channel_params = {
    "Google": {
        "attribution_rate": 0.22,
        "ctr": (0.035, 0.005),
        "cvr": (0.024, 0.003),
        "cpc": (0.85, 0.10),
        "base_clicks": (8, 20)
    },
    "Meta": {
        "attribution_rate": 0.18,
        "ctr": (0.012, 0.002),
        "cvr": (0.016, 0.002),
        "cpc": (0.60, 0.08),
        "base_clicks": (6, 18)
    },
    "Display": {
        "attribution_rate": 0.04,
        "ctr": (0.0025, 0.0004),
        "cvr": (0.004, 0.0008),
        "cpm": (4.50, 0.50), # cost per 1k impressions
        "base_clicks": (12, 30)
    },
    "Retargeting": {
        "attribution_rate": 0.09,
        "ctr": (0.018, 0.003),
        "cvr": (0.052, 0.006),
        "cpc": (0.95, 0.12),
        "base_clicks": (2, 8)
    }
}

# Apply custom boosts to specific campaigns to make the dataset interesting and realistic
# E.g. Health_Beauty does better on social media (Meta), Tech Accessories does better on search (Google)
def get_customized_params(category, channel):
    params = channel_params[channel].copy()
    
    # Beauty on Meta is highly effective
    if category == "beleza_saude" and channel == "Meta":
        params["attribution_rate"] = 0.28
        params["cvr"] = (0.026, 0.003)
        params["ctr"] = (0.018, 0.002)
    # Computers Accessories on Google is highly effective
    elif category == "informatica_acessorios" and channel == "Google":
        params["attribution_rate"] = 0.32
        params["cvr"] = (0.032, 0.004)
        params["ctr"] = (0.045, 0.005)
    # Watches & Gifts on Retargeting converts very well (high value item)
    elif category == "relogios_presentes" and channel == "Retargeting":
        params["attribution_rate"] = 0.15
        params["cvr"] = (0.075, 0.008)
    # Display for Bed & Bath has high impressions but very low CVR
    elif category == "cama_mesa_banho" and channel == "Display":
        params["attribution_rate"] = 0.03
        params["ctr"] = (0.0032, 0.0005)
        params["cvr"] = (0.003, 0.0005)
        
    return params

print("Simulating metrics for each campaign day...")
simulated_records = []

for idx, row in full_df.iterrows():
    cat = row['product_category']
    chan = row['channel']
    n_orders = row['actual_orders']
    revenue = row['actual_revenue']
    
    params = get_customized_params(cat, chan)
    
    # 1. Simulate Attributed Orders
    att_rate = params["attribution_rate"]
    if n_orders > 0:
        # Attributed orders follows a Poisson distribution around the expected value
        # bounded by the actual orders
        expected_orders = n_orders * att_rate
        att_orders = np.random.poisson(expected_orders)
        att_orders = min(att_orders, n_orders)
    else:
        att_orders = 0
        
    # 2. Simulate Attributed Revenue
    if att_orders > 0 and n_orders > 0:
        # Scale revenue proportionally to the fraction of orders attributed
        att_revenue = round(revenue * (att_orders / n_orders), 2)
    else:
        att_revenue = 0.0
        
    # 3. Simulate CVR and Clicks
    mean_cvr, std_cvr = params["cvr"]
    cvr = max(0.001, np.random.normal(mean_cvr, std_cvr))
    
    if att_orders > 0:
        # Back-calculate clicks from attributed orders
        clicks = int(round(att_orders / cvr))
        # Add small random variation to clicks
        clicks = int(round(clicks * np.random.uniform(0.9, 1.1)))
        clicks = max(att_orders, clicks) # Clicks must be >= orders
    else:
        # Baseline clicks when there are no sales
        min_clicks, max_clicks = params["base_clicks"]
        clicks = np.random.randint(min_clicks, max_clicks + 1)
        
    # 4. Simulate CTR and Impressions
    mean_ctr, std_ctr = params["ctr"]
    ctr = max(0.0005, np.random.normal(mean_ctr, std_ctr))
    
    impressions = int(round(clicks / ctr))
    impressions = max(clicks + np.random.randint(5, 50), impressions) # Impressions must be > clicks
    
    # 5. Simulate Cost and Spend
    if chan == "Display":
        # Display is CPM based
        mean_cpm, std_cpm = params["cpm"]
        cpm = max(1.0, np.random.normal(mean_cpm, std_cpm))
        ad_spend = round((impressions / 1000.0) * cpm, 2)
    else:
        # Google, Meta, Retargeting are CPC based
        mean_cpc, std_cpc = params["cpc"]
        cpc = max(0.10, np.random.normal(mean_cpc, std_cpc))
        ad_spend = round(clicks * cpc, 2)
        
    # Edge case: if clicks is 0, make sure impressions are low and spend is 0
    if clicks == 0:
        impressions = np.random.randint(10, 100)
        ad_spend = 0.0
        
    simulated_records.append({
        "date": row['date'],
        "campaign_id": row['campaign_id'],
        "campaign_name": row['campaign_name'],
        "channel": chan,
        "product_category": cat,
        "product_category_eng": row['product_category_eng'],
        "impressions": impressions,
        "clicks": clicks,
        "ad_spend": ad_spend,
        "attributed_orders": att_orders,
        "attributed_revenue": att_revenue
    })

simulated_df = pd.DataFrame(simulated_records)

# Sort by date and campaign_id
simulated_df = simulated_df.sort_values(by=['date', 'campaign_id']).reset_index(drop=True)

# Save to CSV
print(f"Saving simulated dataset to {output_path}...")
simulated_df.to_csv(output_path, index=False)
print("Simulation successful!")
print(f"Generated {len(simulated_df)} daily campaign records.")
print("\nFirst 5 rows:")
print(simulated_df.head())
print("\nAggregate Channel Summary:")
summary = simulated_df.groupby('channel').agg(
    total_spend=('ad_spend', 'sum'),
    total_clicks=('clicks', 'sum'),
    total_impressions=('impressions', 'sum'),
    total_attributed_orders=('attributed_orders', 'sum'),
    total_attributed_revenue=('attributed_revenue', 'sum')
).reset_index()
summary['CTR'] = summary['total_clicks'] / summary['total_impressions']
summary['CVR'] = summary['total_attributed_orders'] / summary['total_clicks']
summary['ROAS'] = summary['total_attributed_revenue'] / summary['total_spend']
print(summary.to_string(index=False))
