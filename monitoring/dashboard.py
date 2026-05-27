import streamlit as st
import asyncio
import pandas as pd
import plotly.express as px
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
import os
from dotenv import load_dotenv

load_dotenv()

def get_async_engine():
    database_url = os.getenv("DATABASE_URL")
    return create_async_engine(database_url, echo=False)


async def fetch_market_kpis(engine) -> dict:
    query = text("""
    WITH latest_prices AS (
        SELECT lp.product_id, lp.supplier_id,
            ROW_NUMBER() OVER (PARTITION BY lp.product_id, lp.supplier_id ORDER BY lp.created_at DESC) as rn
        FROM monitor.price_history lp
        JOIN public.suppliers s ON lp.supplier_id = s.id
        WHERE s.name != 'Базовый поставщик'
    ),
    current_active AS (
        SELECT product_id, supplier_id FROM latest_prices WHERE rn = 1
    ),
    competitors_density AS (
        SELECT product_id, COUNT(DISTINCT supplier_id) as s_count
        FROM current_active
        GROUP BY product_id
    )
    SELECT 
        (SELECT COUNT(DISTINCT id) FROM public.products WHERE is_active = true) as total_products,
        (SELECT COUNT(DISTINCT id) FROM public.suppliers WHERE name != 'Базовый поставщик') as total_suppliers,
        ROUND(AVG(s_count), 2) as avg_density
    FROM competitors_density;
    """)
    async with engine.connect() as conn:
        df = await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))
    return df.iloc[0].to_dict() if not df.empty else {}


async def fetch_price_changes(engine) -> pd.Series:
    query = text("""
    WITH price_history_with_prev AS (
        SELECT 
            ph.product_id, ph.supplier_id, ph.price, ph.created_at,
            LAG(ph.price) OVER (PARTITION BY ph.product_id, ph.supplier_id ORDER BY ph.created_at) as prev_price
        FROM monitor.price_history ph
        JOIN public.suppliers s ON ph.supplier_id = s.id
        WHERE s.name != 'Базовый поставщик'
    ),
    daily_changes AS (
        SELECT 
            DATE(created_at) as change_date,
            COUNT(*) as changes_count
        FROM price_history_with_prev
        WHERE prev_price IS NOT NULL AND price != prev_price
        GROUP BY DATE(created_at)
    ),
    ranked_days AS (
        SELECT change_date, changes_count, ROW_NUMBER() OVER (ORDER BY change_date DESC) as rn
        FROM daily_changes
    )
    SELECT 
        (SELECT changes_count FROM ranked_days WHERE rn = 1) as last_day_changes,
        (SELECT changes_count FROM ranked_days WHERE rn = 2) as prev_day_changes,
        (SELECT change_date FROM ranked_days WHERE rn = 1) as last_day_date,
        (SELECT change_date FROM ranked_days WHERE rn = 2) as prev_day_date;
    """)
    async with engine.connect() as conn:
        df = await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))
    return df.iloc[0] if not df.empty else None


async def fetch_top_assortment(engine) -> pd.DataFrame:
    query = text("""
    WITH latest_prices AS (
        SELECT product_id, supplier_id,
            ROW_NUMBER() OVER (PARTITION BY product_id, supplier_id ORDER BY created_at DESC) as rn
        FROM monitor.price_history
    )
    SELECT s.name as supplier_name, COUNT(DISTINCT lp.product_id) as assortment_size
    FROM latest_prices lp
    JOIN public.suppliers s ON lp.supplier_id = s.id
    WHERE lp.rn = 1 AND s.name != 'Базовый поставщик'
    GROUP BY s.name
    ORDER BY assortment_size DESC
    LIMIT 10;
    """)
    async with engine.connect() as conn:
        return await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))


async def fetch_cheapest_suppliers(engine) -> pd.DataFrame:
    query = text("""
    WITH latest_prices AS (
        SELECT product_id, supplier_id, price,
            ROW_NUMBER() OVER (PARTITION BY product_id, supplier_id ORDER BY created_at DESC) as rn
        FROM monitor.price_history
    ),
    current_active_prices AS (
        SELECT lp.product_id, lp.supplier_id, lp.price 
        FROM latest_prices lp
        JOIN public.suppliers s ON lp.supplier_id = s.id
        WHERE lp.rn = 1 AND s.name != 'Базовый поставщик'
    ),
    min_prices_per_product AS (
        SELECT product_id, MIN(price) as min_price
        FROM current_active_prices
        GROUP BY product_id
        HAVING COUNT(DISTINCT supplier_id) > 1
    ),
    cheapest_suppliers AS (
        SELECT cap.supplier_id, COUNT(*) as lowest_price_count
        FROM current_active_prices cap
        JOIN min_prices_per_product mpp ON cap.product_id = mpp.product_id AND cap.price = mpp.min_price
        GROUP BY cap.supplier_id
    )
    SELECT s.name as supplier_name, COALESCE(cs.lowest_price_count, 0) as lowest_price_count
    FROM cheapest_suppliers cs
    JOIN public.suppliers s ON cs.supplier_id = s.id
    ORDER BY lowest_price_count DESC
    LIMIT 10;
    """)
    async with engine.connect() as conn:
        return await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))


async def fetch_active_products(engine) -> pd.DataFrame:
    query = text("SELECT id, name FROM public.products WHERE is_active = true ORDER BY name;")
    async with engine.connect() as conn:
        return await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))


async def fetch_product_latest_prices(engine, product_id: int) -> pd.DataFrame:
    query = text("""
    WITH ranked_prices AS (
        SELECT 
            ph.supplier_id,
            s.name as supplier_name,
            ph.price,
            ph.created_at,
            ROW_NUMBER() OVER (PARTITION BY ph.supplier_id ORDER BY ph.created_at DESC) as rn
        FROM monitor.price_history ph
        JOIN public.suppliers s ON ph.supplier_id = s.id
        WHERE ph.product_id = :product_id AND s.name != 'Базовый поставщик'
    )
    SELECT supplier_name, price, created_at
    FROM ranked_prices
    WHERE rn = 1;
    """)
    async with engine.connect() as conn:
        return await conn.run_sync(
            lambda sync_conn: pd.read_sql(query, sync_conn, params={"product_id": product_id})
        )


async def fetch_product_history(engine, product_id: int) -> pd.DataFrame:
    query = text("""
    SELECT 
        s.name as supplier_name,
        ph.price,
        ph.created_at
    FROM monitor.price_history ph
    JOIN public.suppliers s ON ph.supplier_id = s.id
    WHERE ph.product_id = :product_id AND s.name != 'Базовый поставщик'
    ORDER BY ph.created_at;
    """)
    async with engine.connect() as conn:
        return await conn.run_sync(
            lambda sync_conn: pd.read_sql(query, sync_conn, params={"product_id": product_id})
        )


async def fetch_suppliers_list(engine) -> pd.DataFrame:
    query = text("SELECT id, name FROM public.suppliers WHERE name != 'Базовый поставщик' ORDER BY name;")
    async with engine.connect() as conn:
        return await conn.run_sync(lambda sync_conn: pd.read_sql(query, sync_conn))


async def fetch_supplier_products_comparison(engine, supplier_id: int) -> pd.DataFrame:
    query = text("""
    WITH latest_prices AS (
        SELECT lp.product_id, lp.supplier_id, lp.price,
            ROW_NUMBER() OVER (PARTITION BY lp.product_id, lp.supplier_id ORDER BY lp.created_at DESC) as rn
        FROM monitor.price_history lp
        JOIN public.suppliers s ON lp.supplier_id = s.id
        WHERE s.name != 'Базовый поставщик'
    ),
    current_prices AS (
        SELECT product_id, supplier_id, price 
        FROM latest_prices WHERE rn = 1
    ),
    market_stats AS (
        SELECT 
            product_id,
            MIN(price) as min_price,
            ROUND(AVG(price), 2) as avg_price
        FROM current_prices
        GROUP BY product_id
    )
    SELECT 
        p.name as product_name,
        cp.price as supplier_price,
        ms.min_price as market_min_price,
        ms.avg_price as market_avg_price
    FROM current_prices cp
    JOIN public.products p ON cp.product_id = p.id
    JOIN market_stats ms ON cp.product_id = ms.product_id
    WHERE cp.supplier_id = :supplier_id;
    """)
    async with engine.connect() as conn:
        return await conn.run_sync(
            lambda sync_conn: pd.read_sql(query, sync_conn, params={"supplier_id": supplier_id})
        )


async def run_ui():
    st.set_page_config(
        page_title="Аналитический BI Дашборд",
        page_icon="📈",
        layout="wide"
    )

    st.title("📈 Мониторинг рынка и анализ цен поставщиков")
    st.markdown("Интерактивный дашборд для BI-аналитика на базе асинхронной архитектуры.")

    engine = get_async_engine()

    try:
        tab_overview, tab_product, tab_supplier = st.tabs([
            "📊 Общий обзор рынка", 
            "🔍 Анализ конкретного товара", 
            "🏢 Аналитика поставщиков"
        ])

        with tab_overview:
            st.subheader("Сводная статистика")
            
            with st.spinner("Загрузка общей статистики..."):
                kpis = await fetch_market_kpis(engine)
                changes_data = await fetch_price_changes(engine)
                df_assortment = await fetch_top_assortment(engine)
                df_cheapest = await fetch_cheapest_suppliers(engine)

            if kpis:
                col_p, col_s, col_d, col_c = st.columns(4)
                col_p.metric("Всего активных товаров", f"{kpis['total_products']:,}")
                col_s.metric("Всего поставщиков", f"{kpis['total_suppliers']:,}")
                col_d.metric("Средняя плотность конкуренции", f"{kpis['avg_density']} пост./тов.")
                
                if changes_data is not None and pd.notna(changes_data['last_day_changes']):
                    last_val = int(changes_data['last_day_changes'])
                    prev_val = int(changes_data['prev_day_changes']) if pd.notna(changes_data['prev_day_changes']) else 0
                    delta = last_val - prev_val
                    col_c.metric(
                        label=f"Изменений цен на {changes_data['last_day_date']}", 
                        value=f"{last_val:,}", 
                        delta=f"{delta:+} vs {changes_data['prev_day_date'] if pd.notna(changes_data['prev_day_date']) else 'пред. день'}"
                    )
                else:
                    col_c.info("Мало данных по динамике цен")

            st.markdown("---")

            col_l, col_r = st.columns(2)
            with col_l:
                st.write("**💼 Топ-10 поставщиков по ширине ассортимента**")
                if not df_assortment.empty:
                    fig1 = px.bar(
                        df_assortment, x='assortment_size', y='supplier_name', orientation='h',
                        color='assortment_size', color_continuous_scale='Blues',
                        labels={'assortment_size': 'Количество товаров', 'supplier_name': 'Поставщик'}
                    )
                    fig1.update_layout(yaxis={'categoryorder': 'total ascending'}, showlegend=False, coloraxis_showscale=False)
                    st.plotly_chart(fig1, use_container_width=True)
                else:
                    st.write("Нет данных.")

            with col_r:
                st.write("**🏆 Лидеры по лучшей цене среди конкурентов (где поставщиков > 1)**")
                if not df_cheapest.empty:
                    fig2 = px.bar(
                        df_cheapest, x='lowest_price_count', y='supplier_name', orientation='h',
                        color='lowest_price_count', color_continuous_scale='Greens',
                        labels={'lowest_price_count': 'Кол-во товаров с мин. ценой', 'supplier_name': 'Поставщик'}
                    )
                    fig2.update_layout(yaxis={'categoryorder': 'total ascending'}, showlegend=False, coloraxis_showscale=False)
                    st.plotly_chart(fig2, use_container_width=True)
                else:
                    st.write("Нет товаров с активной конкуренцией.")

        with tab_product:
            st.subheader("Глубокий анализ ценообразования товара")
            
            df_products = await fetch_active_products(engine)
            
            if not df_products.empty:
                selected_product_name = st.selectbox("Выберите товар для анализа:", df_products['name'])
                selected_product_id = int(df_products[df_products['name'] == selected_product_name]['id'].values[0])

                with st.spinner("Загрузка данных по товару..."):
                    df_latest = await fetch_product_latest_prices(engine, selected_product_id)
                    df_history = await fetch_product_history(engine, selected_product_id)

                if not df_latest.empty:
                    min_row = df_latest.loc[df_latest['price'].idxmin()]
                    max_row = df_latest.loc[df_latest['price'].idxmax()]
                    spread_pct = round(((max_row['price'] - min_row['price']) / min_row['price']) * 100, 2)

                    col_min, col_max, col_spread = st.columns(3)
                    col_min.metric("Минимальная цена", f"{min_row['price']:,} руб.", f"Поставщик: {min_row['supplier_name']}")
                    col_max.metric("Максимальная цена", f"{max_row['price']:,} руб.", f"Поставщик: {max_row['supplier_name']}", delta_color="inverse")
                    col_spread.metric("Рыночный спред (разброс цен)", f"{spread_pct}%", "Разница min и max цен")

                    st.markdown("---")

                    col_hist, col_comp = st.columns([2, 1])
                    with col_hist:
                        st.write("**📈 История изменения цен поставщиков во времени**")
                        if not df_history.empty:
                            fig_line = px.line(
                                df_history, x='created_at', y='price', color='supplier_name',
                                labels={'created_at': 'Дата фиксации', 'price': 'Цена, руб.', 'supplier_name': 'Поставщик'},
                                markers=True
                            )
                            st.plotly_chart(fig_line, use_container_width=True)
                        else:
                            st.write("История изменений отсутствует.")

                    with col_comp:
                        st.write("**📊 Сравнение текущих цен поставщиков**")
                        fig_bar = px.bar(
                            df_latest, x='supplier_name', y='price', color='price',
                            color_continuous_scale='Viridis',
                            labels={'supplier_name': 'Поставщик', 'price': 'Цена, руб.'}
                        )
                        fig_bar.update_layout(coloraxis_showscale=False)
                        st.plotly_chart(fig_bar, use_container_width=True)
                else:
                    st.warning("По данному товару еще нет зарегистрированных цен.")
            else:
                st.warning("В базе данных нет активных товаров.")

        with tab_supplier:
            st.subheader("Сравнительный анализ поставщика")
            
            df_suppliers = await fetch_suppliers_list(engine)

            if not df_suppliers.empty:
                selected_supplier_name = st.selectbox("Выберите поставщика:", df_suppliers['name'])
                selected_supplier_id = int(df_suppliers[df_suppliers['name'] == selected_supplier_name]['id'].values[0])

                with st.spinner("Загрузка аналитики поставщика..."):
                    df_sup_comp = await fetch_supplier_products_comparison(engine, selected_supplier_id)

                if not df_sup_comp.empty:
                    total_sup_products = len(df_sup_comp)
                    cheapest_count = len(df_sup_comp[df_sup_comp['supplier_price'] == df_sup_comp['market_min_price']])
                    best_price_share = round((cheapest_count / total_sup_products) * 100, 2) if total_sup_products > 0 else 0

                    col_tot, col_ch, col_sh = st.columns(3)
                    col_tot.metric("Поставляемый ассортимент", f"{total_sup_products} тов.")
                    col_ch.metric("Товаров по лучшей цене (min)", f"{cheapest_count} тов.")
                    col_sh.metric("Доля лидерства по цене", f"{best_price_share}%", "Доля лучших цен в ассортименте")

                    st.markdown("---")
                    
                    product_options = sorted(df_sup_comp['product_name'].unique())
                    selected_products = st.multiselect(
                        "Выберите товары для сравнения на графике (по умолчанию показаны первые 15):",
                        options=product_options,
                        default=product_options[:15]
                    )

                    if selected_products:
                        df_filtered = df_sup_comp[df_sup_comp['product_name'].isin(selected_products)]
                        
                        df_melted = df_filtered.melt(
                            id_vars=['product_name'], 
                            value_vars=['supplier_price', 'market_min_price', 'market_avg_price'],
                            var_name='Price_Type', 
                            value_name='Price_Value'
                        )
                        price_map = {
                            'supplier_price': 'Цена этого поставщика',
                            'market_min_price': 'Минимальная на рынке',
                            'market_avg_price': 'Средняя на рынке'
                        }
                        df_melted['Price_Type'] = df_melted['Price_Type'].map(price_map)

                        st.write("**📊 Сравнение цен поставщика со средними и минимальными ценами рынка**")
                        fig_sup_comp = px.bar(
                            df_melted, x='product_name', y='Price_Value', color='Price_Type',
                            barmode='group',
                            labels={'product_name': 'Товар', 'Price_Value': 'Цена, руб.', 'Price_Type': 'Метрика цены'},
                            color_discrete_sequence=px.colors.qualitative.Pastel
                        )
                        st.plotly_chart(fig_sup_comp, use_container_width=True)
                    else:
                        st.info("Пожалуйста, выберите хотя бы один товар для отображения на графике.")
                else:
                    st.warning("У данного поставщика нет актуальных цен на товары.")
            else:
                st.warning("В базе данных нет зарегистрированных поставщиков.")

    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run_ui())