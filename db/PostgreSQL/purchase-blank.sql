﻿-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/01.types-domains-tables-and-constraints/tables-and-constraints.sql --<--<--
DROP SCHEMA IF EXISTS purchase CASCADE;
CREATE SCHEMA purchase;

CREATE TABLE purchase.price_types
(
    price_type_id                           SERIAL PRIMARY KEY,
    price_type_code                         national character varying(24) NOT NULL,
    price_type_name                         national character varying(500) NOT NULL,
    audit_user_id                           integer REFERENCES account.users,
    audit_ts                                TIMESTAMP WITH TIME ZONE DEFAULT(NOW()),
	deleted									boolean DEFAULT(false)
);

CREATE UNIQUE INDEX price_types_price_type_code_uix
ON purchase.price_types(UPPER(price_type_code))
WHERE NOT deleted;

CREATE UNIQUE INDEX price_types_price_type_name_uix
ON purchase.price_types(UPPER(price_type_name))
WHERE NOT deleted;

CREATE TABLE purchase.item_cost_prices
(   
    item_cost_price_id                      BIGSERIAL PRIMARY KEY,
    item_id                                 integer NOT NULL REFERENCES inventory.items,
    unit_id                                 integer NOT NULL REFERENCES inventory.units,
    supplier_id                             integer REFERENCES inventory.suppliers,
    lead_time_in_days                       integer NOT NULL DEFAULT(0),
    includes_tax                            boolean NOT NULL
                                            CONSTRAINT item_cost_prices_includes_tax_df   
                                            DEFAULT(false),
    price                                   public.money_strict NOT NULL,
    audit_user_id                           integer REFERENCES account.users,
    audit_ts                                TIMESTAMP WITH TIME ZONE DEFAULT(NOW()),
	deleted									boolean DEFAULT(false)
);

CREATE UNIQUE INDEX item_cost_prices_item_id_unit_id_supplier_id_uix
ON purchase.item_cost_prices(item_id, unit_id, supplier_id)
WHERE NOT deleted;

CREATE TABLE purchase.purchases
(
    purchase_id                             BIGSERIAL PRIMARY KEY,
    checkout_id                             bigint NOT NULL REFERENCES inventory.checkouts,
    supplier_id                             integer NOT NULL REFERENCES inventory.suppliers,
	price_type_id							integer NOT NULL REFERENCES purchase.price_types
);


CREATE TABLE purchase.purchase_returns
(
    purchase_return_id                      BIGSERIAL PRIMARY KEY,
    purchase_id                             bigint NOT NULL REFERENCES purchase.purchases,
    checkout_id                             bigint NOT NULL REFERENCES inventory.checkouts,
    supplier_id                             integer NOT NULL REFERENCES inventory.suppliers   
);


CREATE TABLE purchase.quotations
(
    quotation_id                            BIGSERIAL PRIMARY KEY,
    value_date                              date NOT NULL,
	expected_delivery_date					date NOT NULL,
    transaction_timestamp                   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT(NOW()),
    supplier_id                             integer NOT NULL REFERENCES inventory.customers,
    price_type_id                           integer NOT NULL REFERENCES purchase.price_types,
	shipper_id								integer REFERENCES inventory.shippers,
    user_id                                 integer NOT NULL REFERENCES account.users,
    office_id                               integer NOT NULL REFERENCES core.offices,
    reference_number                        national character varying(24),
	terms									national character varying(500),
    internal_memo                           national character varying(500),
    audit_user_id                           integer REFERENCES account.users,
    audit_ts                                TIMESTAMP WITH TIME ZONE DEFAULT(NOW()),
	deleted									boolean DEFAULT(false)
);

CREATE TABLE purchase.quotation_details
(
    quotation_detail_id                     BIGSERIAL PRIMARY KEY,
    quotation_id                            bigint NOT NULL REFERENCES purchase.quotations,
    value_date                              date NOT NULL,
    item_id                                 integer NOT NULL REFERENCES inventory.items,
    price                                   public.money_strict NOT NULL,
    discount_rate                           public.decimal_strict2 NOT NULL DEFAULT(0),    
    tax                                     public.money_strict2 NOT NULL DEFAULT(0),    
    shipping_charge                         public.money_strict2 NOT NULL DEFAULT(0),    
    unit_id                                 integer NOT NULL REFERENCES inventory.units,
    quantity                                public.decimal_strict2 NOT NULL
);


CREATE TABLE purchase.orders
(
    order_id                                BIGSERIAL PRIMARY KEY,
    quotation_id                            bigint REFERENCES purchase.quotations,
    value_date                              date NOT NULL,
	expected_delivery_date					date NOT NULL,
    transaction_timestamp                   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT(NOW()),
    supplier_id                             integer NOT NULL REFERENCES inventory.suppliers,
    price_type_id                           integer NOT NULL REFERENCES purchase.price_types,
	shipper_id								integer REFERENCES inventory.shippers,
    user_id                                 integer NOT NULL REFERENCES account.users,
    office_id                               integer NOT NULL REFERENCES core.offices,
    reference_number                        national character varying(24),
    terms                                   national character varying(500),
    internal_memo                           national character varying(500),
    audit_user_id                           integer REFERENCES account.users,
    audit_ts                                TIMESTAMP WITH TIME ZONE DEFAULT(NOW()),
	deleted									boolean DEFAULT(false)
);

CREATE TABLE purchase.order_details
(
    order_detail_id                         BIGSERIAL PRIMARY KEY,
    order_id                                bigint NOT NULL REFERENCES purchase.orders,
    value_date                              date NOT NULL,
    item_id                                 integer NOT NULL REFERENCES inventory.items,
    price                                   public.money_strict NOT NULL,
    discount_rate                           public.decimal_strict2 NOT NULL DEFAULT(0),    
    tax                                     public.money_strict2 NOT NULL DEFAULT(0),    
    shipping_charge                         public.money_strict2 NOT NULL DEFAULT(0),    
    unit_id                                 integer NOT NULL REFERENCES inventory.units,
    quantity                                public.decimal_strict2 NOT NULL
);

CREATE TYPE purchase.purchase_detail_type
AS
(
    store_id            integer,
	transaction_type	national character varying(2),
    item_id           	integer,
    quantity            public.integer_strict,
    unit_id           	integer,
    price               public.money_strict,
    discount            public.money_strict2,
    tax                 public.money_strict2,
    shipping_charge     public.money_strict2
);



-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_item_cost_price.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_item_cost_price(_item_id integer, _supplier_id bigint, _unit_id integer);

CREATE FUNCTION purchase.get_item_cost_price(_item_id integer, _supplier_id bigint, _unit_id integer)
RETURNS public.money_strict2
STABLE
AS
$$
    DECLARE _price              public.money_strict2;
    DECLARE _costing_unit_id    integer;
    DECLARE _factor             decimal(30, 6);
  
BEGIN
    --Fist pick the catalog price which matches all these fields:
    --Item, Customer Type, Price Type, and Unit.
    --This is the most effective price.
    SELECT 
        purchase.item_cost_prices.price, 
        purchase.item_cost_prices.unit_id
    INTO 
        _price,
        _costing_unit_id
    FROM purchase.item_cost_prices
    WHERE purchase.item_cost_prices.item_id=_item_id
    AND purchase.item_cost_prices.supplier_id =_supplier_id
    AND purchase.item_cost_prices.unit_id = _unit_id
    AND NOT purchase.item_cost_prices.deleted;


    IF(_costing_unit_id IS NULL) THEN
        --We do not have a cost price of this item for the unit supplied.
        --Let's see if this item has a price for other units.
        SELECT 
            purchase.item_cost_prices.price, 
            purchase.item_cost_prices.unit_id
        INTO 
            _price, 
            _costing_unit_id
        FROM purchase.item_cost_prices
        WHERE purchase.item_cost_prices.item_id=_item_id
        AND purchase.item_cost_prices.supplier_id =_supplier_id
	AND NOT purchase.item_cost_prices.deleted;
    END IF;

    
    IF(_price IS NULL) THEN
        --This item does not have cost price defined in the catalog.
        --Therefore, getting the default cost price from the item definition.
        SELECT 
            cost_price, 
            unit_id
        INTO 
            _price, 
            _costing_unit_id
        FROM inventory.items
        WHERE inventory.items.item_id = _item_id
		AND NOT inventory.items.deleted;
    END IF;

        --Get the unitary conversion factor if the requested unit does not match with the price defition.
    _factor := inventory.convert_unit(_unit_id, _costing_unit_id);
    RETURN _price * _factor;
END
$$
LANGUAGE plpgsql;

--SELECT * FROM purchase.get_item_cost_price(6, 1, 7);


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_order_view.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_order_view
(
    _user_id                        integer,
    _office_id                      integer,
    _supplier                       national character varying(500),
    _from                           date,
    _to                             date,
    _expected_from                  date,
    _expected_to                    date,
    _id                             bigint,
    _reference_number               national character varying(500),
    _internal_memo                  national character varying(500),
    _terms                          national character varying(500),
    _posted_by                      national character varying(500),
    _office                         national character varying(500)
);

CREATE FUNCTION purchase.get_order_view
(
    _user_id                        integer,
    _office_id                      integer,
    _supplier                       national character varying(500),
    _from                           date,
    _to                             date,
    _expected_from                  date,
    _expected_to                    date,
    _id                             bigint,
    _reference_number               national character varying(500),
    _internal_memo                  national character varying(500),
    _terms                          national character varying(500),
    _posted_by                      national character varying(500),
    _office                         national character varying(500)
)
RETURNS TABLE
(
    id                              bigint,
    supplier                        national character varying(500),
    value_date                      date,
    expected_date                   date,
    reference_number                national character varying(24),
    terms                           national character varying(500),
    internal_memo                   national character varying(500),
    posted_by                       national character varying(500),
    office                          national character varying(500),
    transaction_ts                  TIMESTAMP WITH TIME ZONE
)
AS
$$
BEGIN
    RETURN QUERY
    WITH RECURSIVE office_cte(office_id) AS 
    (
        SELECT _office_id
        UNION ALL
        SELECT
            c.office_id
        FROM 
        office_cte AS p, 
        core.offices AS c 
        WHERE 
        parent_office_id = p.office_id
    )

    SELECT 
        purchase.orders.order_id,
        inventory.get_supplier_name_by_supplier_id(purchase.orders.supplier_id),
        purchase.orders.value_date,
        purchase.orders.expected_delivery_date,
        purchase.orders.reference_number,
        purchase.orders.terms,
        purchase.orders.internal_memo,
        account.get_name_by_user_id(purchase.orders.user_id)::national character varying(500) AS posted_by,
        core.get_office_name_by_office_id(office_id)::national character varying(500) AS office,
        purchase.orders.transaction_timestamp
    FROM purchase.orders
    WHERE 1 = 1
    AND purchase.orders.value_date BETWEEN _from AND _to
    AND purchase.orders.expected_delivery_date BETWEEN _expected_from AND _expected_to
    AND purchase.orders.office_id IN (SELECT office_id FROM office_cte)
    AND (COALESCE(_id, 0) = 0 OR _id = purchase.orders.order_id)
    AND COALESCE(LOWER(purchase.orders.reference_number), '') LIKE '%' || LOWER(_reference_number) || '%' 
    AND COALESCE(LOWER(purchase.orders.internal_memo), '') LIKE '%' || LOWER(_internal_memo) || '%' 
    AND COALESCE(LOWER(purchase.orders.terms), '') LIKE '%' || LOWER(_terms) || '%' 
    AND LOWER(inventory.get_customer_name_by_customer_id(purchase.orders.supplier_id)) LIKE '%' || LOWER(_supplier) || '%' 
    AND LOWER(account.get_name_by_user_id(purchase.orders.user_id)) LIKE '%' || LOWER(_posted_by) || '%' 
    AND LOWER(core.get_office_name_by_office_id(purchase.orders.office_id)) LIKE '%' || LOWER(_office) || '%' 
    AND NOT purchase.orders.deleted;
END
$$
LANGUAGE plpgsql;


--SELECT * FROM purchase.get_order_view(1,1,'', '11/27/2010','11/27/2016','1-1-2000','1-1-2020', null,'','','','', '');


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_price_type_id_by_price_type_code.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_price_type_id_by_price_type_code(_price_type_code national character varying(24));

CREATE FUNCTION purchase.get_price_type_id_by_price_type_code(_price_type_code national character varying(24))
RETURNS integer
AS
$$
BEGIN
    RETURN purchase.price_types.price_type_id
    FROM purchase.price_types
    WHERE purchase.price_types.price_type_code = _price_type_code;
END
$$
LANGUAGE plpgsql;

-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_price_type_id_by_price_type_name.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_price_type_id_by_price_type_name(_price_type_name national character varying(24));

CREATE FUNCTION purchase.get_price_type_id_by_price_type_name(_price_type_name national character varying(24))
RETURNS integer
AS
$$
BEGIN
    RETURN purchase.price_types.price_type_id
    FROM purchase.price_types
    WHERE purchase.price_types.price_type_name = _price_type_name;
END
$$
LANGUAGE plpgsql;

-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_quotation_view.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_quotation_view
(
    _user_id                        integer,
    _office_id                      integer,
    _supplier                       national character varying(500),
    _from                           date,
    _to                             date,
    _expected_from                  date,
    _expected_to                    date,
    _id                             bigint,
    _reference_number               national character varying(500),
    _internal_memo                  national character varying(500),
    _terms                          national character varying(500),
    _posted_by                      national character varying(500),
    _office                         national character varying(500)
);

CREATE FUNCTION purchase.get_quotation_view
(
    _user_id                        integer,
    _office_id                      integer,
    _supplier                       national character varying(500),
    _from                           date,
    _to                             date,
    _expected_from                  date,
    _expected_to                    date,
    _id                             bigint,
    _reference_number               national character varying(500),
    _internal_memo                  national character varying(500),
    _terms                          national character varying(500),
    _posted_by                      national character varying(500),
    _office                         national character varying(500)
)
RETURNS TABLE
(
    id                              bigint,
    supplier                        national character varying(500),
    value_date                      date,
    expected_date                   date,
    reference_number                national character varying(24),
    terms                           national character varying(500),
    internal_memo                   national character varying(500),
    posted_by                       national character varying(500),
    office                          national character varying(500),
    transaction_ts                  TIMESTAMP WITH TIME ZONE
)
AS
$$
BEGIN
    RETURN QUERY
    WITH RECURSIVE office_cte(office_id) AS 
    (
        SELECT _office_id
        UNION ALL
        SELECT
            c.office_id
        FROM 
        office_cte AS p, 
        core.offices AS c 
        WHERE 
        parent_office_id = p.office_id
    )

    SELECT 
        purchase.quotations.quotation_id,
        inventory.get_supplier_name_by_supplier_id(purchase.quotations.supplier_id),
        purchase.quotations.value_date,
        purchase.quotations.expected_delivery_date,
        purchase.quotations.reference_number,
        purchase.quotations.terms,
        purchase.quotations.internal_memo,
        account.get_name_by_user_id(purchase.quotations.user_id)::national character varying(500) AS posted_by,
        core.get_office_name_by_office_id(office_id)::national character varying(500) AS office,
        purchase.quotations.transaction_timestamp
    FROM purchase.quotations
    WHERE 1 = 1
    AND purchase.quotations.value_date BETWEEN _from AND _to
    AND purchase.quotations.expected_delivery_date BETWEEN _expected_from AND _expected_to
    AND purchase.quotations.office_id IN (SELECT office_id FROM office_cte)
    AND (COALESCE(_id, 0) = 0 OR _id = purchase.quotations.quotation_id)
    AND COALESCE(LOWER(purchase.quotations.reference_number), '') LIKE '%' || LOWER(_reference_number) || '%' 
    AND COALESCE(LOWER(purchase.quotations.internal_memo), '') LIKE '%' || LOWER(_internal_memo) || '%' 
    AND COALESCE(LOWER(purchase.quotations.terms), '') LIKE '%' || LOWER(_terms) || '%' 
    AND LOWER(inventory.get_customer_name_by_customer_id(purchase.quotations.supplier_id)) LIKE '%' || LOWER(_supplier) || '%' 
    AND LOWER(account.get_name_by_user_id(purchase.quotations.user_id)) LIKE '%' || LOWER(_posted_by) || '%' 
    AND LOWER(core.get_office_name_by_office_id(purchase.quotations.office_id)) LIKE '%' || LOWER(_office) || '%' 
    AND NOT purchase.quotations.deleted;
END
$$
LANGUAGE plpgsql;


--SELECT * FROM purchase.get_quotation_view(1,1,'', '11/27/2010','11/27/2016','1-1-2000','1-1-2020', null,'','','','', '');


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.get_supplier_id_by_supplier_code.sql --<--<--
DROP FUNCTION IF EXISTS purchase.get_supplier_id_by_supplier_code(text);

CREATE FUNCTION purchase.get_supplier_id_by_supplier_code(text)
RETURNS bigint
AS
$$
BEGIN
    RETURN
    (
        SELECT
            supplier_id
        FROM
            inventory.suppliers
        WHERE 
            inventory.suppliers.supplier_code=$1
	AND NOT
	    inventory.suppliers.deleted
    );
END
$$
LANGUAGE plpgsql;



-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.post_purchase.sql --<--<--
DROP FUNCTION IF EXISTS purchase.post_purchase
(
    _office_id                              integer,
    _user_id                                integer,
    _login_id                               bigint,
    _value_date                             date,
    _book_date                              date,
    _cost_center_id                         integer,
    _reference_number                       national character varying(24),
    _statement_reference                    text,
    _supplier_id                            integer,
    _price_type_id                          integer,
    _shipper_id                             integer,
    _details                                purchase.purchase_detail_type[]
);


CREATE FUNCTION purchase.post_purchase
(
    _office_id                              integer,
    _user_id                                integer,
    _login_id                               bigint,
    _value_date                             date,
    _book_date                              date,
    _cost_center_id                         integer,
    _reference_number                       national character varying(24),
    _statement_reference                    text,
    _supplier_id                            integer,
    _price_type_id                          integer,
    _shipper_id                             integer,
    _details                                purchase.purchase_detail_type[]
)
RETURNS bigint
AS
$$
    DECLARE _transaction_master_id          bigint;
    DECLARE _checkout_id                    bigint;
    DECLARE _checkout_detail_id             bigint;
    DECLARE _shipping_address_id            integer;
    DECLARE _grand_total                    public.money_strict;
    DECLARE _discount_total                 public.money_strict2;
    DECLARE _payable                        public.money_strict2;
    DECLARE _default_currency_code          national character varying(12);
    DECLARE _is_periodic                    boolean = inventory.is_periodic_inventory(_office_id);
    DECLARE _tran_counter                   integer;
    DECLARE _transaction_code               text;
    DECLARE _tax_total                      public.money_strict2;
    DECLARE _tax_account_id                 integer;
    DECLARE _shipping_charge                public.money_strict2;
    DECLARE _book_name                      national character varying(100) = 'Purchase';
BEGIN
    IF NOT finance.can_post_transaction(_login_id, _user_id, _office_id, _book_name, _value_date) THEN
        RETURN 0;
    END IF;

    _tax_account_id                         := finance.get_sales_tax_account_id_by_office_id(_office_id);

    IF(_supplier_id IS NULL) THEN
        RAISE EXCEPTION '%', 'Invalid supplier';
    END IF;
    
    DROP TABLE IF EXISTS temp_checkout_details CASCADE;
    CREATE TEMPORARY TABLE temp_checkout_details
    (
        id                              	SERIAL PRIMARY KEY,
        checkout_id                     	bigint, 
        store_id                        	integer,
        transaction_type                	national character varying(2),
        item_id                         	integer, 
        quantity                        	public.integer_strict,
        unit_id                         	integer,
        base_quantity                   	decimal(30, 6),
        base_unit_id                    	integer,
        price                           	public.money_strict NOT NULL DEFAULT(0),
        cost_of_goods_sold              	public.money_strict2 NOT NULL DEFAULT(0),
        discount                        	public.money_strict2 NOT NULL DEFAULT(0),
        tax                                 public.money_strict2 NOT NULL DEFAULT(0),
        shipping_charge                     public.money_strict2 NOT NULL DEFAULT(0),
        purchase_account_id             	integer, 
        purchase_discount_account_id    	integer, 
        inventory_account_id            	integer
    ) ON COMMIT DROP;



    INSERT INTO temp_checkout_details(store_id, transaction_type, item_id, quantity, unit_id, price, discount, tax, shipping_charge)
    SELECT store_id, transaction_type, item_id, quantity, unit_id, price, discount, tax, shipping_charge
    FROM explode_array(_details);


    UPDATE temp_checkout_details 
    SET
        base_quantity                   	= inventory.get_base_quantity_by_unit_id(unit_id, quantity),
        base_unit_id                    	= inventory.get_root_unit_id(unit_id),
        purchase_account_id             	= inventory.get_purchase_account_id(item_id),
        purchase_discount_account_id    	= inventory.get_purchase_discount_account_id(item_id),
        inventory_account_id            	= inventory.get_inventory_account_id(item_id);    
    
    IF EXISTS
    (
            SELECT 1 FROM temp_checkout_details AS details
            WHERE inventory.is_valid_unit_id(details.unit_id, details.item_id) = false
            LIMIT 1
    ) THEN
        RAISE EXCEPTION 'Item/unit mismatch.'
        USING ERRCODE='P3201';
    END IF;

    SELECT SUM(COALESCE(discount, 0))                               INTO _discount_total FROM temp_checkout_details;
    SELECT SUM(COALESCE(price, 0) * COALESCE(quantity, 0))          INTO _grand_total FROM temp_checkout_details;
    SELECT SUM(COALESCE(shipping_charge, 0))                        INTO _shipping_charge FROM temp_checkout_details;
   SELECT SUM(COALESCE(tax, 0))                                     INTO _tax_total FROM temp_checkout_details;


    DROP TABLE IF EXISTS temp_transaction_details;
    CREATE TEMPORARY TABLE temp_transaction_details
    (
        transaction_master_id       		BIGINT, 
        tran_type                   		national character varying(4), 
        account_id                  		integer, 
        statement_reference         		text, 
        currency_code               		national character varying(12), 
        amount_in_currency          		public.money_strict, 
        local_currency_code         		national character varying(12), 
        er                          		decimal_strict, 
        amount_in_local_currency    		public.money_strict
    ) ON COMMIT DROP;

    _payable                                := _grand_total - COALESCE(_discount_total, 0) + COALESCE(_shipping_charge, 0) + COALESCE(_tax_total, 0);
    _default_currency_code              	:= core.get_currency_code_by_office_id(_office_id);
    _transaction_master_id  				:= nextval(pg_get_serial_sequence('finance.transaction_master', 'transaction_master_id'));
    _checkout_id            				:= nextval(pg_get_serial_sequence('inventory.checkouts', 'checkout_id'));
    _tran_counter           				:= finance.get_new_transaction_counter(_value_date);
    _transaction_code       				:= finance.get_transaction_code(_value_date, _office_id, _user_id, _login_id);

    IF(_is_periodic = true) THEN
        INSERT INTO temp_transaction_details(tran_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Dr', purchase_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0)), 1, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0))
        FROM temp_checkout_details
        GROUP BY purchase_account_id;
    ELSE
        --Perpetutal Inventory Accounting System
        INSERT INTO temp_transaction_details(tran_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Dr', inventory_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0)), 1, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0))
        FROM temp_checkout_details
        GROUP BY inventory_account_id;
    END IF;


    IF(_discount_total > 0) THEN
        INSERT INTO temp_transaction_details(tran_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Cr', purchase_discount_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(discount, 0)), 1, _default_currency_code, SUM(COALESCE(discount, 0))
        FROM temp_checkout_details
        GROUP BY purchase_discount_account_id;
    END IF;

    IF(COALESCE(_tax_total, 0) > 0) THEN
        INSERT INTO temp_transaction_details(tran_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Dr', _tax_account_id, _statement_reference, _default_currency_code, _tax_total, 1, _default_currency_code, _tax_total;
    END IF;	

    INSERT INTO temp_transaction_details(tran_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
    SELECT 'Cr', inventory.get_account_id_by_supplier_id(_supplier_id), _statement_reference, _default_currency_code, _payable, 1, _default_currency_code, _payable;

    --RAISE EXCEPTION '%', _BOOK_DATE;



    UPDATE temp_transaction_details     SET transaction_master_id   = _transaction_master_id;
    UPDATE temp_checkout_details           SET checkout_id         = _checkout_id;
    
    INSERT INTO finance.transaction_master(transaction_master_id, transaction_counter, transaction_code, book, value_date, book_date, user_id, login_id, office_id, cost_center_id, reference_number, statement_reference) 
    SELECT _transaction_master_id, _tran_counter, _transaction_code, _book_name, _value_date, _book_date, _user_id, _login_id, _office_id, _cost_center_id, _reference_number, _statement_reference;

    
    INSERT INTO finance.transaction_details(value_date, book_date, office_id, transaction_master_id, tran_type, account_id, statement_reference, currency_code, amount_in_currency, local_currency_code, er, amount_in_local_currency)
    SELECT _value_date, _book_date, _office_id, transaction_master_id, tran_type, account_id, statement_reference, currency_code, amount_in_currency, local_currency_code, er, amount_in_local_currency
    FROM temp_transaction_details
    ORDER BY tran_type DESC;


    INSERT INTO inventory.checkouts(value_date, book_date, checkout_id, transaction_master_id, transaction_book, posted_by, shipper_id, office_id)
    SELECT _value_date, _book_date, _checkout_id, _transaction_master_id, _book_name, _user_id, _shipper_id, _office_id;

    INSERT INTO purchase.purchases(checkout_id, supplier_id, price_type_id)
    SELECT _checkout_id, _supplier_id, _price_type_id;

    INSERT INTO inventory.checkout_details(checkout_id, value_date, book_date, store_id, transaction_type, item_id, price, discount, cost_of_goods_sold, tax, shipping_charge, unit_id, quantity, base_unit_id, base_quantity)
    SELECT _checkout_id, _value_date, _book_date, store_id, transaction_type, item_id, price, discount, cost_of_goods_sold, tax, shipping_charge, unit_id, quantity, base_unit_id, base_quantity
    FROM temp_checkout_details;
    
    PERFORM finance.auto_verify(_transaction_master_id, _office_id);
    RETURN _transaction_master_id;
END
$$
LANGUAGE plpgsql;



-- SELECT * FROM purchase.post_purchase(1, 1, 1, finance.get_value_date(1), finance.get_value_date(1), 1, '', '', 1, 1, NULL,
-- ARRAY[
-- ROW(1, 'Dr', 1, 1, 1,180000, 0, 10, 200)::purchase.purchase_detail_type,
-- ROW(1, 'Dr', 2, 1, 7,130000, 300, 10, 30)::purchase.purchase_detail_type,
-- ROW(1, 'Dr', 3, 1, 1,110000, 5000, 10, 50)::purchase.purchase_detail_type]);
-- 


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/02.functions-and-logic/purchase.post_return.sql --<--<--
DROP FUNCTION IF EXISTS purchase.post_return
(
    _transaction_master_id                  bigint,
    _office_id                              integer,
    _user_id                                integer,
    _login_id                               bigint,
    _value_date                             date,
    _book_date                              date,
    _cost_center_id                         integer,
    _supplier_id                            integer,
    _price_type_id                          integer,
    _shipper_id                             integer,
    _reference_number                       national character varying(24),
    _statement_reference                    text,
    _details                                purchase.purchase_detail_type[]
);

CREATE FUNCTION purchase.post_return
(
    _transaction_master_id                  bigint,
    _office_id                              integer,
    _user_id                                integer,
    _login_id                               bigint,
    _value_date                             date,
    _book_date                              date,
    _cost_center_id                         integer,
    _supplier_id                            integer,
    _price_type_id                          integer,
    _shipper_id                             integer,
    _reference_number                       national character varying(24),
    _statement_reference                    text,
    _details                                purchase.purchase_detail_type[]
)
RETURNS bigint
AS
$$
    DECLARE _purchase_id                    bigint;
    DECLARE _original_price_type_id         integer;
    DECLARE _tran_master_id                 bigint;
    DECLARE _checkout_detail_id             bigint;
    DECLARE _tran_counter                   integer;
    DECLARE _transaction_code               text;
    DECLARE _checkout_id                    bigint;
    DECLARE _grand_total                    public.money_strict;
    DECLARE _discount_total                 public.money_strict2;
    DECLARE _tax_total                      public.money_strict2;
    DECLARE _credit_account_id              integer;
    DECLARE _default_currency_code          national character varying(12);
    DECLARE _sm_id                          bigint;
    DECLARE this                            RECORD;
    DECLARE _is_periodic                    boolean = inventory.is_periodic_inventory(_office_id);
    DECLARE _book_name                      text='Purchase Return';
    DECLARE _receivable                     public.money_strict;
    DECLARE _tax_account_id                 integer;
BEGIN    
    IF NOT finance.can_post_transaction(_login_id, _user_id, _office_id, _book_name, _value_date) THEN
        RETURN 0;
    END IF;

    CREATE TEMPORARY TABLE temp_checkout_details
    (
        id                                  SERIAL PRIMARY KEY,
        checkout_id                         bigint, 
        transaction_type                    national character varying(2), 
        store_id                            integer,
        item_code                           text,
        item_id                             integer, 
        quantity                            public.integer_strict,
        unit_name                           text,
        unit_id                             integer,
        base_quantity                       decimal(30, 6),
        base_unit_id                        integer,                
        price                               public.money_strict,
        discount                            public.money_strict2,
        tax                                 public.money_strict2,
        shipping_charge                     public.money_strict2,
        purchase_account_id                 integer, 
        purchase_discount_account_id        integer, 
        inventory_account_id                integer
    ) ON COMMIT DROP;

    CREATE TEMPORARY TABLE temp_transaction_details
    (
        transaction_master_id               BIGINT, 
        transaction_type                    national character varying(2), 
        account_id                          integer, 
        statement_reference                 text, 
        currency_code                       national character varying(12), 
        amount_in_currency                  public.money_strict, 
        local_currency_code                 national character varying(12), 
        er                                  decimal_strict, 
        amount_in_local_currency            public.money_strict
    ) ON COMMIT DROP;
   

    SELECT purchase.purchases.purchase_id INTO _purchase_id
    FROM purchase.purchases
    INNER JOIN inventory.checkouts
    ON inventory.checkouts.checkout_id = purchase.purchases.checkout_id
    INNER JOIN finance.transaction_master
    ON finance.transaction_master.transaction_master_id = inventory.checkouts.transaction_master_id
    WHERE finance.transaction_master.transaction_master_id = _transaction_master_id;

    SELECT purchase.purchases.price_type_id INTO _original_price_type_id
    FROM purchase.purchases
    WHERE purchase.purchases.purchase_id = _purchase_id;

    IF(_price_type_id != _original_price_type_id) THEN
        RAISE EXCEPTION 'Please select the right price type.'
        USING ERRCODE='P3271';
    END IF;
    
	SELECT checkout_id INTO _sm_id 
	FROM inventory.checkouts 
	WHERE inventory.checkouts.transaction_master_id = _transaction_master_id
	AND NOT inventory.checkouts.deleted;

    INSERT INTO temp_checkout_details(store_id, transaction_type, item_id, quantity, unit_id, price, discount, tax, shipping_charge)
	SELECT store_id, transaction_type, item_id, quantity, unit_id, price, discount, tax, shipping_charge
	FROM explode_array(_details);

    UPDATE temp_checkout_details 
    SET
        base_quantity                   = inventory.get_base_quantity_by_unit_id(unit_id, quantity),
        base_unit_id                    = inventory.get_root_unit_id(unit_id),
        purchase_account_id             = inventory.get_purchase_account_id(item_id),
        purchase_discount_account_id    = inventory.get_purchase_discount_account_id(item_id),
        inventory_account_id            = inventory.get_inventory_account_id(item_id);    


    IF EXISTS
    (
        SELECT 1 FROM temp_checkout_details AS details
        WHERE inventory.is_valid_unit_id(details.unit_id, details.item_id) = false
        LIMIT 1
    ) THEN
        RAISE EXCEPTION 'Item/unit mismatch.'
        USING ERRCODE='P3201';
    END IF;

    
    _tax_account_id                     := finance.get_sales_tax_account_id_by_office_id(_office_id);
    _default_currency_code              := core.get_currency_code_by_office_id(_office_id);
    _tran_master_id                     := nextval(pg_get_serial_sequence('finance.transaction_master', 'transaction_master_id'));
    _checkout_id                        := nextval(pg_get_serial_sequence('inventory.checkouts', 'checkout_id'));
    _tran_counter                       := finance.get_new_transaction_counter(_value_date);
    _transaction_code                   := finance.get_transaction_code(_value_date, _office_id, _user_id, _login_id);
       
    SELECT SUM(COALESCE(tax, 0))                                INTO _tax_total FROM temp_checkout_details;
    SELECT SUM(COALESCE(discount, 0))                           INTO _discount_total FROM temp_checkout_details;
    SELECT SUM(COALESCE(price, 0) * COALESCE(quantity, 0))      INTO _grand_total FROM temp_checkout_details;

    _receivable := _grand_total + _tax_total - COALESCE(_discount_total, 0);



    IF(_is_periodic = true) THEN        
        INSERT INTO temp_transaction_details(transaction_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Cr', purchase_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0)), 1, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0))
        FROM temp_checkout_details
        GROUP BY purchase_account_id;
    ELSE
        --Perpetutal Inventory Accounting System
        INSERT INTO temp_transaction_details(transaction_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Cr', inventory_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0)), 1, _default_currency_code, SUM(COALESCE(price, 0) * COALESCE(quantity, 0))
        FROM temp_checkout_details
        GROUP BY inventory_account_id;
    END IF;


    IF(COALESCE(_discount_total, 0) > 0) THEN
        INSERT INTO temp_transaction_details(transaction_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Dr', purchase_discount_account_id, _statement_reference, _default_currency_code, SUM(COALESCE(discount, 0)), 1, _default_currency_code, SUM(COALESCE(discount, 0))
        FROM temp_checkout_details
        GROUP BY purchase_discount_account_id;
    END IF;

    IF(COALESCE(_tax_total, 0) > 0) THEN
        INSERT INTO temp_transaction_details(transaction_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
        SELECT 'Cr', _tax_account_id, _statement_reference, _default_currency_code, _tax_total, 1, _default_currency_code, _tax_total;
    END IF;

    --RAISE EXCEPTION '%', array_to_string(ARRAY(SELECT temp_transaction_details.*::text FROM temp_transaction_details), E'\n');

    INSERT INTO temp_transaction_details(transaction_type, account_id, statement_reference, currency_code, amount_in_currency, er, local_currency_code, amount_in_local_currency)
    SELECT 'Dr', inventory.get_account_id_by_supplier_id(_supplier_id), _statement_reference, _default_currency_code, _receivable, 1, _default_currency_code, _receivable;


    UPDATE temp_transaction_details        SET transaction_master_id   = _tran_master_id;
    UPDATE temp_checkout_details           SET checkout_id             = _checkout_id;



    INSERT INTO finance.transaction_master(transaction_master_id, transaction_counter, transaction_code, book, value_date, book_date, user_id, login_id, office_id, cost_center_id, reference_number, statement_reference) 
    SELECT _tran_master_id, _tran_counter, _transaction_code, _book_name, _value_date, _book_date, _user_id, _login_id, _office_id, _cost_center_id, _reference_number, _statement_reference;


    INSERT INTO finance.transaction_details(office_id, value_date, book_date, transaction_master_id, tran_type, account_id, statement_reference, currency_code, amount_in_currency, local_currency_code, er, amount_in_local_currency)
    SELECT _office_id, _value_date, _book_date, transaction_master_id, transaction_type, account_id, statement_reference, currency_code, amount_in_currency, local_currency_code, er, amount_in_local_currency
    FROM temp_transaction_details
    ORDER BY transaction_type DESC;


    INSERT INTO inventory.checkouts(value_date, book_date, checkout_id, transaction_master_id, transaction_book, posted_by, office_id, shipper_id)
    SELECT _value_date, _book_date, _checkout_id, _tran_master_id, _book_name, _user_id, _office_id, _shipper_id;
            
    FOR this IN SELECT * FROM temp_checkout_details ORDER BY id
    LOOP
        _checkout_detail_id        := nextval(pg_get_serial_sequence('inventory.checkout_details', 'checkout_detail_id'));

        INSERT INTO inventory.checkout_details(checkout_detail_id, value_date, book_date, checkout_id, transaction_type, store_id, item_id, quantity, unit_id, base_quantity, base_unit_id, price, discount, tax, shipping_charge)
        SELECT _checkout_detail_id, _value_date, _book_date, this.checkout_id, this.transaction_type, this.store_id, this.item_id, this.quantity, this.unit_id, this.base_quantity, this.base_unit_id, this.price, this.discount, this.tax, this.shipping_charge
        FROM temp_checkout_details
        WHERE id = this.id;        
    END LOOP;

    INSERT INTO purchase.purchase_returns(checkout_id, purchase_id, supplier_id)
    SELECT _checkout_id, _purchase_id, _supplier_id;

    
    PERFORM finance.auto_verify(_transaction_master_id, _office_id);
    RETURN _tran_master_id;
END
$$
LANGUAGE plpgsql;


-- SELECT * FROM purchase.post_return
-- (
--     1,
--     1,
--     1,
--     1,
--     finance.get_value_date(1),
--     finance.get_value_date(1),
--     1,
--     1,
--     1,
--     1,
--     '',
--     '',
--     ARRAY[
--         ROW(1, 'Dr', 1, 1, 1,180000, 0, 1200, 200)::purchase.purchase_detail_type,
--         ROW(1, 'Dr', 2, 1, 7,130000, 300, 1200, 30)::purchase.purchase_detail_type,
--         ROW(1, 'Dr', 3, 1, 1,110000, 5000, 1200, 50)::purchase.purchase_detail_type
--         ]
-- );

-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/03.menus/menus.sql --<--<--
DELETE FROM auth.menu_access_policy
WHERE menu_id IN
(
    SELECT menu_id FROM core.menus
    WHERE app_name = 'Purchase'
);

DELETE FROM auth.group_menu_access_policy
WHERE menu_id IN
(
    SELECT menu_id FROM core.menus
    WHERE app_name = 'Purchase'
);

DELETE FROM core.menus
WHERE app_name = 'Purchase';


SELECT * FROM core.create_app('Purchase', 'Purchase', '1.0', 'MixERP Inc.', 'December 1, 2015', 'newspaper yellow', '/dashboard/purchase/tasks/entry', NULL::text[]);

SELECT * FROM core.create_menu('Purchase', 'Tasks', '', 'lightning', '');
SELECT * FROM core.create_menu('Purchase', 'Purchase Entry', '/dashboard/purchase/tasks/entry', 'write', 'Tasks');
SELECT * FROM core.create_menu('Purchase', 'Purchase Returns', '/dashboard/purchase/tasks/return', 'minus', 'Tasks');
SELECT * FROM core.create_menu('Purchase', 'Purchase Quotation', '/dashboard/purchase/tasks/quotation', 'newspaper', 'Tasks');
SELECT * FROM core.create_menu('Purchase', 'Purchase Orders', '/dashboard/purchase/tasks/order', 'file text outline', 'Tasks');
SELECT * FROM core.create_menu('Purchase', 'Purchase Verification', '/dashboard/purchase/tasks/entry/verification', 'checkmark', 'Tasks');
SELECT * FROM core.create_menu('Purchase', 'Purchase Return Verification', '/dashboard/purchase/tasks/return/verification', 'minus', 'Tasks');

SELECT * FROM core.create_menu('Purchase', 'Setup', 'square outline', 'configure', '');
SELECT * FROM core.create_menu('Purchase', 'Suppliers', '/dashboard/purchase/setup/suppliers', 'users', 'Setup');
SELECT * FROM core.create_menu('Purchase', 'Price Types', '/dashboard/purchase/setup/price-types', 'dollar', 'Setup');
SELECT * FROM core.create_menu('Purchase', 'Cost Prices', '/dashboard/purchase/setup/cost-prices', 'rupee', 'Setup');

SELECT * FROM core.create_menu('Purchase', 'Reports', '', 'block layout', '');
SELECT * FROM core.create_menu('Purchase', 'Top Suppliers', '/dashboard/reports/view/Areas/MixERP.Purchases/Reports/TopSuppliers.xml', 'spy', 'Reports');
SELECT * FROM core.create_menu('Purchase', 'Low Inventory Products', '/dashboard/reports/view/Areas/MixERP.Purchases/Reports/LowInventory.xml', 'warning', 'Reports');
SELECT * FROM core.create_menu('Purchase', 'Out of Stock Products', '/dashboard/reports/view/Areas/MixERP.Purchases/Reports/OutOfStock.xml', 'remove circle', 'Reports');
SELECT * FROM core.create_menu('Purchase', 'Supplier Contacts', '/dashboard/reports/view/Areas/MixERP.Purchases/Reports/SupplierContacts.xml', 'remove circle', 'Reports');


SELECT * FROM auth.create_app_menu_policy
(
    'Admin', 
    core.get_office_id_by_office_name('Default'), 
    'Purchase',
    '{*}'::text[]
);



-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/04.default-values/01.default-values.sql --<--<--
INSERT INTO purchase.price_types(price_type_code, price_type_name)
SELECT 'RET',   'Retail' UNION ALL
SELECT 'WHO',   'Wholesale';


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/05.scrud-views/purchase.item_cost_price_scrud_view.sql --<--<--
DROP VIEW IF EXISTS purchase.item_cost_price_scrud_view;

CREATE VIEW purchase.item_cost_price_scrud_view
AS
SELECT
    purchase.item_cost_prices.item_cost_price_id,
    purchase.item_cost_prices.item_id,
    inventory.items.item_code || ' (' || inventory.items.item_name || ')' AS item,
    purchase.item_cost_prices.unit_id,
    inventory.units.unit_code || ' (' || inventory.units.unit_name || ')' AS unit,
    purchase.item_cost_prices.supplier_id,
    inventory.suppliers.supplier_code || ' (' || inventory.suppliers.supplier_name || ')' AS supplier,
    purchase.item_cost_prices.lead_time_in_days,
    purchase.item_cost_prices.includes_tax,
    purchase.item_cost_prices.price
FROM purchase.item_cost_prices
INNER JOIN inventory.items
ON inventory.items.item_id = purchase.item_cost_prices.item_id
INNER JOIN inventory.units
ON inventory.units.unit_id = purchase.item_cost_prices.unit_id
INNER JOIN inventory.suppliers
ON inventory.suppliers.supplier_id = purchase.item_cost_prices.supplier_id
WHERE NOT purchase.item_cost_prices.deleted;


-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/05.views/purchase.item_view.sql --<--<--
DROP VIEW IF EXISTS purchase.item_view;

CREATE VIEW purchase.item_view
AS
SELECT
    inventory.items.item_id,
    inventory.items.item_code,
    inventory.items.item_name,
    inventory.items.is_taxable_item,
    inventory.items.barcode,
    inventory.items.item_group_id,
    inventory.item_groups.item_group_name,
    inventory.item_types.item_type_id,
    inventory.item_types.item_type_name,
    inventory.items.brand_id,
    inventory.brands.brand_name,
    inventory.items.preferred_supplier_id,
    inventory.items.unit_id,
    array_to_string(inventory.get_associated_unit_list(inventory.items.unit_id), ',') AS valid_units,
    inventory.units.unit_code,
    inventory.units.unit_name,
    inventory.items.hot_item,
    inventory.items.cost_price,
    inventory.items.cost_price_includes_tax,
    inventory.items.photo
FROM inventory.items
INNER JOIN inventory.item_groups
ON inventory.item_groups.item_group_id = inventory.items.item_group_id
INNER JOIN inventory.item_types
ON inventory.item_types.item_type_id = inventory.items.item_type_id
INNER JOIN inventory.brands
ON inventory.brands.brand_id = inventory.items.brand_id
INNER JOIN inventory.units
ON inventory.units.unit_id = inventory.items.unit_id
WHERE NOT inventory.items.deleted
AND inventory.items.allow_purchase
AND inventory.items.maintain_inventory;

-->-->-- src/Frapid.Web/Areas/MixERP.Purchases/db/PostgreSQL/2.x/2.0/src/99.ownership.sql --<--<--
DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT * FROM pg_tables 
    WHERE NOT schemaname = ANY(ARRAY['pg_catalog', 'information_schema'])
    AND tableowner <> 'frapid_db_user'
    LOOP
        EXECUTE 'ALTER TABLE '|| this.schemaname || '.' || this.tablename ||' OWNER TO frapid_db_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;

DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT oid::regclass::text as mat_view
    FROM   pg_class
    WHERE  relkind = 'm'
    LOOP
        EXECUTE 'ALTER TABLE '|| this.mat_view ||' OWNER TO frapid_db_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;

DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT 'ALTER '
        || CASE WHEN p.proisagg THEN 'AGGREGATE ' ELSE 'FUNCTION ' END
        || quote_ident(n.nspname) || '.' || quote_ident(p.proname) || '(' 
        || pg_catalog.pg_get_function_identity_arguments(p.oid) || ') OWNER TO frapid_db_user;' AS sql
    FROM   pg_catalog.pg_proc p
    JOIN   pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE  NOT n.nspname = ANY(ARRAY['pg_catalog', 'information_schema'])
    LOOP        
        EXECUTE this.sql;
    END LOOP;
END
$$
LANGUAGE plpgsql;


DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT * FROM pg_views
    WHERE NOT schemaname = ANY(ARRAY['pg_catalog', 'information_schema'])
    AND viewowner <> 'frapid_db_user'
    LOOP
        EXECUTE 'ALTER VIEW '|| this.schemaname || '.' || this.viewname ||' OWNER TO frapid_db_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;


DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT 'ALTER SCHEMA ' || nspname || ' OWNER TO frapid_db_user;' AS sql FROM pg_namespace
    WHERE nspname NOT LIKE 'pg_%'
    AND nspname <> 'information_schema'
    LOOP
        EXECUTE this.sql;
    END LOOP;
END
$$
LANGUAGE plpgsql;



DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'frapid_db_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT      'ALTER TYPE ' || n.nspname || '.' || t.typname || ' OWNER TO frapid_db_user;' AS sql
    FROM        pg_type t 
    LEFT JOIN   pg_catalog.pg_namespace n ON n.oid = t.typnamespace 
    WHERE       (t.typrelid = 0 OR (SELECT c.relkind = 'c' FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid)) 
    AND         NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid)
    AND         typtype NOT IN ('b')
    AND         n.nspname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        EXECUTE this.sql;
    END LOOP;
END
$$
LANGUAGE plpgsql;


DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'report_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT * FROM pg_tables 
    WHERE NOT schemaname = ANY(ARRAY['pg_catalog', 'information_schema'])
    AND tableowner <> 'report_user'
    LOOP
        EXECUTE 'GRANT SELECT ON TABLE '|| this.schemaname || '.' || this.tablename ||' TO report_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;

DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'report_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT oid::regclass::text as mat_view
    FROM   pg_class
    WHERE  relkind = 'm'
    LOOP
        EXECUTE 'GRANT SELECT ON TABLE '|| this.mat_view  ||' TO report_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;

DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'report_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT 'GRANT EXECUTE ON '
        || CASE WHEN p.proisagg THEN 'AGGREGATE ' ELSE 'FUNCTION ' END
        || quote_ident(n.nspname) || '.' || quote_ident(p.proname) || '(' 
        || pg_catalog.pg_get_function_identity_arguments(p.oid) || ') TO report_user;' AS sql
    FROM   pg_catalog.pg_proc p
    JOIN   pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE  NOT n.nspname = ANY(ARRAY['pg_catalog', 'information_schema'])
    LOOP        
        EXECUTE this.sql;
    END LOOP;
END
$$
LANGUAGE plpgsql;


DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'report_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT * FROM pg_views
    WHERE NOT schemaname = ANY(ARRAY['pg_catalog', 'information_schema'])
    AND viewowner <> 'report_user'
    LOOP
        EXECUTE 'GRANT SELECT ON '|| this.schemaname || '.' || this.viewname ||' TO report_user;';
    END LOOP;
END
$$
LANGUAGE plpgsql;


DO
$$
    DECLARE this record;
BEGIN
    IF(CURRENT_USER = 'report_user') THEN
        RETURN;
    END IF;

    FOR this IN 
    SELECT 'GRANT USAGE ON SCHEMA ' || nspname || ' TO report_user;' AS sql FROM pg_namespace
    WHERE nspname NOT LIKE 'pg_%'
    AND nspname <> 'information_schema'
    LOOP
        EXECUTE this.sql;
    END LOOP;
END
$$
LANGUAGE plpgsql;


