DO $$ BEGIN
    ALTER TYPE edge_source ADD VALUE IF NOT EXISTS 'topic_cooccurrence';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
