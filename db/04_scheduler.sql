-- =====================================================================
-- OPTIONAL. Only run this if your Oracle user has CREATE JOB privilege
-- (most student XE accounts do, by default, for their own schema).
-- This makes expire_listings() run automatically every hour instead
-- of only when POST /api/admin/expire-listings is called by hand.
-- =====================================================================

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'expire_listings_job',
        job_type        => 'STORED_PROCEDURE',
        job_action      => 'EXPIRE_LISTINGS',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=HOURLY',
        enabled         => TRUE
    );
END;
/

-- To check it's running:
-- SELECT job_name, state, last_start_date, next_run_date FROM user_scheduler_jobs;

-- To remove it later:
-- BEGIN DBMS_SCHEDULER.DROP_JOB('expire_listings_job'); END;
-- /
