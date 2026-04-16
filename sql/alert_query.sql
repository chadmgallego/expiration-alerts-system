-- Document Expiration Alert System
-- Alert Query
--
-- Pulls all documents that qualify for an alert based on four tiered windows:
--   - expired:   past expiration date, alert every 7 days
--   - <= 30 days: always alert weekly (gated by 7-day cooldown on last_alert_sent)
--   - 31-60 days: fires once, only if stepping down from 90-day alert or never alerted
--   - 61-90 days: fires once, only if document has never been alerted before
 
SELECT 
    s.name, 
    d.document_type, 
    d.expiration_date,
    h.email,
    (d.expiration_date - CURRENT_DATE) AS days_left,
    CASE 
        WHEN d.expiration_date < CURRENT_DATE                      THEN 'EXPIRED'
        WHEN d.expiration_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'URGENT!' 
        ELSE NULL 
    END AS urgency,
    d.expired,
    d.last_alert_sent,
    d.last_alert_type,
    d.document_id
FROM DOCUMENTS d 
JOIN STAFF_AND_DEP s ON d.personal_id = s.personal_id
JOIN HOUSEHOLD_CONTACTS h ON s.household_contact_id = h.household_contact_id
WHERE 
    -- Expired window: past expiration date, alert every 7 days
    (
        d.expiration_date < CURRENT_DATE
        AND (
            d.last_alert_sent IS NULL
            OR d.last_alert_sent <= CURRENT_DATE - INTERVAL '7 days'
        )
    )
    -- 30-day window: weekly, enforced by 7-day cooldown on last_alert_sent
    OR (
        (d.expiration_date - CURRENT_DATE) >= 0
        AND (d.expiration_date - CURRENT_DATE) <= 30
        AND (
            d.last_alert_sent IS NULL
            OR d.last_alert_sent <= CURRENT_DATE - INTERVAL '7 days'
        )
    )
    -- 60-day window: fires once, only if stepping down from 90-day alert or fresh
    OR (
        (d.expiration_date - CURRENT_DATE) > 30
        AND (d.expiration_date - CURRENT_DATE) <= 60
        AND (d.last_alert_type = 90 OR d.last_alert_type IS NULL)
    )
    -- 90-day window: fires once, only if never alerted before
    OR (
        (d.expiration_date - CURRENT_DATE) > 60
        AND (d.expiration_date - CURRENT_DATE) <= 90
        AND d.last_alert_type IS NULL
    );
 
