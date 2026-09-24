-- Sanitized schema extracted from production structure only.
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS=0;

-- custom_profile_details
CREATE TABLE `custom_profile_details` (
  `borrowernumber` int(11) NOT NULL,
  `researcher_uuid` char(36) DEFAULT NULL,
  `preferred_name` varchar(255) DEFAULT NULL,
  `official_name` varchar(255) DEFAULT NULL,
  `alternative_name` varchar(255) DEFAULT NULL,
  `biography` mediumtext DEFAULT NULL,
  `job_title` varchar(255) DEFAULT NULL,
  `main_affiliation` varchar(255) DEFAULT NULL,
  `working_group` varchar(255) DEFAULT NULL,
  `website` varchar(500) DEFAULT NULL,
  `orcid` varchar(100) DEFAULT NULL,
  `scopus_author_id` varchar(100) DEFAULT NULL,
  `researcher_id` varchar(100) DEFAULT NULL,
  `affiliation_role` varchar(255) DEFAULT NULL,
  `affiliation_organisation` varchar(255) DEFAULT NULL,
  `affiliation_start` varchar(100) DEFAULT NULL,
  `affiliation_end` varchar(100) DEFAULT NULL,
  `education_role` varchar(255) DEFAULT NULL,
  `education_organisation` varchar(255) DEFAULT NULL,
  `education_start` varchar(100) DEFAULT NULL,
  `education_end` varchar(100) DEFAULT NULL,
  `qualification_title` varchar(255) DEFAULT NULL,
  `qualification_start` varchar(100) DEFAULT NULL,
  `qualification_end` varchar(100) DEFAULT NULL,
  `qualification_organisation` varchar(255) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `research_interests` mediumtext DEFAULT NULL,
  `oecd_areas` mediumtext DEFAULT NULL,
  `knows_language` mediumtext DEFAULT NULL,
  `profile_status` varchar(50) DEFAULT 'submitted',
  `verification_status` varchar(50) NOT NULL DEFAULT 'pending',
  `employment_status` varchar(50) NOT NULL DEFAULT 'active',
  `sync_enabled` tinyint(1) NOT NULL DEFAULT 1,
  `public_visibility` tinyint(1) NOT NULL DEFAULT 0,
  `verified_by` int(11) DEFAULT NULL,
  `verified_at` datetime DEFAULT NULL,
  `relieving_date` date DEFAULT NULL,
  `status_reason` varchar(500) DEFAULT NULL,
  `last_scopus_sync` datetime DEFAULT NULL,
  `last_wos_sync` datetime DEFAULT NULL,
  `last_orcid_sync` datetime DEFAULT NULL,
  `identity_confidence` decimal(5,2) DEFAULT NULL,
  `identity_decision` varchar(50) DEFAULT NULL,
  `photo_updated_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `first_name` varchar(255) DEFAULT NULL,
  `last_name` varchar(255) DEFAULT NULL,
  `gender` varchar(50) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `profile_url` varchar(500) DEFAULT NULL,
  `user_type` varchar(100) DEFAULT NULL,
  `department` varchar(255) DEFAULT NULL,
  `school` varchar(255) DEFAULT NULL,
  `designation` varchar(255) DEFAULT NULL,
  `joining_date` date DEFAULT NULL,
  `employee_id` varchar(100) DEFAULT NULL,
  `enrollment_id` varchar(100) DEFAULT NULL,
  `google_scholar_profile` varchar(500) DEFAULT NULL,
  `vidwan_id` varchar(100) DEFAULT NULL,
  `eperson_policy` mediumtext DEFAULT NULL,
  `group_policy` mediumtext DEFAULT NULL,
  `custom_url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`borrowernumber`),
  UNIQUE KEY `uq_researcher_uuid` (`researcher_uuid`),
  KEY `profile_status_idx` (`profile_status`),
  KEY `researcher_user_type_idx` (`user_type`),
  KEY `researcher_verification_idx` (`verification_status`),
  KEY `researcher_employment_idx` (`employment_status`),
  KEY `researcher_scopus_idx` (`scopus_author_id`),
  KEY `researcher_wos_idx` (`researcher_id`),
  KEY `researcher_orcid_idx` (`orcid`),
  KEY `researcher_employee_idx` (`employee_id`),
  KEY `researcher_custom_url_idx` (`custom_url`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_affiliations
CREATE TABLE `researcher_affiliations` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `organisation_name` varchar(255) NOT NULL,
  `organisation_identifier` varchar(150) DEFAULT NULL,
  `department` varchar(255) DEFAULT NULL,
  `role_title` varchar(255) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `is_current` tinyint(1) NOT NULL DEFAULT 0,
  `affiliation_type` varchar(50) NOT NULL DEFAULT 'employment',
  `verification_status` varchar(50) NOT NULL DEFAULT 'pending',
  `verified_by` int(11) DEFAULT NULL,
  `verified_at` datetime DEFAULT NULL,
  `source` varchar(50) NOT NULL DEFAULT 'profile',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `researcher_affiliation_borrower_idx` (`borrowernumber`),
  KEY `researcher_affiliation_current_idx` (`is_current`),
  KEY `researcher_affiliation_org_idx` (`organisation_name`),
  KEY `researcher_affiliation_dates_idx` (`start_date`,`end_date`),
  CONSTRAINT `researcher_affiliation_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_audit_log
CREATE TABLE `researcher_audit_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `action_type` varchar(100) NOT NULL,
  `old_value` longtext DEFAULT NULL,
  `new_value` longtext DEFAULT NULL,
  `action_reason` text DEFAULT NULL,
  `performed_by` int(11) DEFAULT NULL,
  `source` varchar(50) NOT NULL DEFAULT 'system',
  `ip_address` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `researcher_audit_borrower_idx` (`borrowernumber`),
  KEY `researcher_audit_action_idx` (`action_type`),
  KEY `researcher_audit_created_idx` (`created_at`),
  CONSTRAINT `researcher_audit_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_author_identity_cache
CREATE TABLE `researcher_author_identity_cache` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `source_name` varchar(50) NOT NULL,
  `source_author_id` varchar(500) NOT NULL,
  `display_name` varchar(255) NOT NULL,
  `published_name` varchar(255) DEFAULT NULL,
  `profile_url` varchar(1000) DEFAULT NULL,
  `orcid` varchar(50) DEFAULT NULL,
  `raw_json` longtext DEFAULT NULL,
  `extraction_method` varchar(100) DEFAULT NULL,
  `first_fetched_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_fetched_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_researcher_source_author` (`borrowernumber`,`source_name`,`source_author_id`),
  KEY `idx_source_author` (`source_name`,`source_author_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_disambiguation_cases
CREATE TABLE `researcher_disambiguation_cases` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `source_name` varchar(50) NOT NULL,
  `source_record_id` varchar(255) DEFAULT NULL,
  `doi` varchar(255) DEFAULT NULL,
  `publication_title` text DEFAULT NULL,
  `candidate_author_name` varchar(500) DEFAULT NULL,
  `candidate_affiliation` text DEFAULT NULL,
  `name_score` decimal(5,2) DEFAULT NULL,
  `identifier_score` decimal(5,2) DEFAULT NULL,
  `affiliation_score` decimal(5,2) DEFAULT NULL,
  `coauthor_score` decimal(5,2) DEFAULT NULL,
  `subject_score` decimal(5,2) DEFAULT NULL,
  `timeline_score` decimal(5,2) DEFAULT NULL,
  `total_score` decimal(5,2) DEFAULT NULL,
  `system_decision` varchar(50) NOT NULL DEFAULT 'review',
  `reviewer_decision` varchar(50) DEFAULT NULL,
  `decision_reason` text DEFAULT NULL,
  `evidence_json` longtext DEFAULT NULL,
  `reviewed_by` int(11) DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `disambiguation_borrower_idx` (`borrowernumber`),
  KEY `disambiguation_source_idx` (`source_name`,`source_record_id`),
  KEY `disambiguation_doi_idx` (`doi`),
  KEY `disambiguation_decision_idx` (`system_decision`,`reviewer_decision`),
  CONSTRAINT `disambiguation_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_employment_episodes
CREATE TABLE `researcher_employment_episodes` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `researcher_uuid` char(36) NOT NULL,
  `borrowernumber` int(11) DEFAULT NULL,
  `organisation_name` varchar(255) NOT NULL,
  `organisation_identifier` varchar(150) DEFAULT NULL,
  `employee_id` varchar(100) DEFAULT NULL,
  `department` varchar(255) DEFAULT NULL,
  `designation` varchar(255) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `episode_status` enum('current','completed') NOT NULL DEFAULT 'current',
  `source` varchar(100) NOT NULL DEFAULT 'koha',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ree_researcher` (`researcher_uuid`),
  KEY `idx_ree_borrower` (`borrowernumber`),
  KEY `idx_ree_employee` (`employee_id`),
  KEY `idx_ree_dates` (`start_date`,`end_date`),
  CONSTRAINT `fk_ree_person` FOREIGN KEY (`researcher_uuid`) REFERENCES `researcher_persons` (`researcher_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_identifiers
CREATE TABLE `researcher_identifiers` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `identifier_type` varchar(50) NOT NULL,
  `identifier_value` varchar(500) NOT NULL,
  `verification_status` varchar(50) NOT NULL DEFAULT 'pending',
  `is_primary` tinyint(1) NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `verification_method` varchar(100) DEFAULT NULL,
  `name_match_score` decimal(5,2) DEFAULT NULL,
  `affiliation_match_score` decimal(5,2) DEFAULT NULL,
  `subject_match_score` decimal(5,2) DEFAULT NULL,
  `overall_confidence` decimal(5,2) DEFAULT NULL,
  `evidence_json` longtext DEFAULT NULL,
  `verified_by` int(11) DEFAULT NULL,
  `verified_at` datetime DEFAULT NULL,
  `last_checked_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `researcher_identifier_unique` (`identifier_type`,`identifier_value`),
  KEY `researcher_identifier_borrower_idx` (`borrowernumber`),
  KEY `researcher_identifier_status_idx` (`verification_status`),
  KEY `idx_rims_identifier_value` (`identifier_type`,`identifier_value`(191)),
  CONSTRAINT `researcher_identifier_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_identity_events
CREATE TABLE `researcher_identity_events` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `researcher_uuid` char(36) NOT NULL,
  `borrowernumber` int(11) DEFAULT NULL,
  `event_type` varchar(100) NOT NULL,
  `old_value` longtext DEFAULT NULL,
  `new_value` longtext DEFAULT NULL,
  `event_reason` text DEFAULT NULL,
  `performed_by` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_rie_researcher` (`researcher_uuid`),
  KEY `idx_rie_event` (`event_type`),
  KEY `idx_rie_created` (`created_at`),
  CONSTRAINT `fk_rie_person` FOREIGN KEY (`researcher_uuid`) REFERENCES `researcher_persons` (`researcher_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_name_variants
CREATE TABLE `researcher_name_variants` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `name_variant` varchar(255) NOT NULL,
  `normalised_variant` varchar(255) DEFAULT NULL,
  `source` varchar(50) NOT NULL DEFAULT 'manual',
  `is_verified` tinyint(1) NOT NULL DEFAULT 0,
  `verified_by` int(11) DEFAULT NULL,
  `verified_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_researcher_name_variant` (`borrowernumber`,`name_variant`),
  KEY `idx_name_variant_normalised` (`normalised_variant`),
  KEY `idx_name_variant_researcher` (`borrowernumber`),
  CONSTRAINT `fk_name_variant_borrower` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_onboarding_log
CREATE TABLE `researcher_onboarding_log` (
  `borrowernumber` int(11) NOT NULL,
  `researcher_type` varchar(100) NOT NULL,
  `email_address` varchar(255) DEFAULT NULL,
  `message_id` int(11) DEFAULT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'pending',
  `queued_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `last_error` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`borrowernumber`),
  KEY `idx_researcher_onboarding_status` (`status`),
  CONSTRAINT `fk_researcher_onboarding_borrower` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- researcher_patron_links
CREATE TABLE `researcher_patron_links` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `researcher_uuid` char(36) NOT NULL,
  `borrowernumber` int(11) NOT NULL,
  `cardnumber` varchar(100) DEFAULT NULL,
  `employee_id` varchar(100) DEFAULT NULL,
  `institutional_email` varchar(255) DEFAULT NULL,
  `link_status` enum('current','former') NOT NULL DEFAULT 'current',
  `valid_from` date DEFAULT NULL,
  `valid_to` date DEFAULT NULL,
  `link_method` varchar(100) DEFAULT 'migration',
  `confidence_score` decimal(5,2) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_researcher_borrower` (`researcher_uuid`,`borrowernumber`),
  UNIQUE KEY `uq_borrower_identity` (`borrowernumber`),
  KEY `idx_rpl_researcher` (`researcher_uuid`),
  KEY `idx_rpl_employee` (`employee_id`),
  KEY `idx_rpl_email` (`institutional_email`),
  KEY `idx_rpl_status` (`link_status`),
  CONSTRAINT `fk_rpl_person` FOREIGN KEY (`researcher_uuid`) REFERENCES `researcher_persons` (`researcher_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_persons
CREATE TABLE `researcher_persons` (
  `researcher_uuid` char(36) NOT NULL,
  `canonical_name` varchar(255) DEFAULT NULL,
  `lifecycle_status` enum('current','former','pending_rejoin','archived') NOT NULL DEFAULT 'current',
  `verification_status` varchar(50) NOT NULL DEFAULT 'pending',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`researcher_uuid`),
  KEY `idx_rp_lifecycle` (`lifecycle_status`),
  KEY `idx_rp_verification` (`verification_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_profile_deletion_log
CREATE TABLE `researcher_profile_deletion_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `deleted_borrowernumber` int(11) NOT NULL,
  `researcher_uuid` char(36) DEFAULT NULL,
  `preferred_name` varchar(255) DEFAULT NULL,
  `official_name` varchar(255) DEFAULT NULL,
  `cardnumber` varchar(32) DEFAULT NULL,
  `orcid` varchar(100) DEFAULT NULL,
  `scopus_author_id` varchar(100) DEFAULT NULL,
  `researcher_id` varchar(100) DEFAULT NULL,
  `deleted_table_counts` longtext DEFAULT NULL,
  `deletion_reason` varchar(1000) NOT NULL,
  `deleted_by` int(11) DEFAULT NULL,
  `patron_account_retained` tinyint(1) NOT NULL DEFAULT 1,
  `deleted_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `deletion_borrower_idx` (`deleted_borrowernumber`),
  KEY `deletion_staff_idx` (`deleted_by`),
  KEY `deletion_date_idx` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_publications_master
CREATE TABLE `researcher_publications_master` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `publication_key` varchar(191) NOT NULL,
  `doi` varchar(255) DEFAULT NULL,
  `normalised_doi` varchar(255) DEFAULT NULL,
  `title` text NOT NULL,
  `normalised_title` text DEFAULT NULL,
  `journal` varchar(500) DEFAULT NULL,
  `publication_date` date DEFAULT NULL,
  `publication_year` smallint(6) DEFAULT NULL,
  `document_type` varchar(150) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `publication_key_unique` (`publication_key`),
  KEY `publication_doi_idx` (`normalised_doi`),
  KEY `publication_year_idx` (`publication_year`),
  KEY `publication_date_idx` (`publication_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_publication_intelligence
CREATE TABLE `researcher_publication_intelligence` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `publication_id` bigint(20) unsigned NOT NULL,
  `master_id` varchar(191) NOT NULL,
  `doi_status` varchar(100) DEFAULT NULL,
  `final_primary_doi` varchar(255) DEFAULT NULL,
  `normalised_final_primary_doi` varchar(255) DEFAULT NULL,
  `doi_reviewed` tinyint(1) NOT NULL DEFAULT 0,
  `review_decision` varchar(100) DEFAULT NULL,
  `review_confidence` decimal(6,3) DEFAULT NULL,
  `human_approval_status` varchar(100) DEFAULT NULL,
  `recommended_action` text DEFAULT NULL,
  `review_reason` text DEFAULT NULL,
  `related_dois_json` longtext DEFAULT NULL,
  `source_names_json` longtext DEFAULT NULL,
  `imported_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `publication_intelligence_publication_unique` (`publication_id`),
  UNIQUE KEY `publication_intelligence_master_unique` (`master_id`),
  KEY `publication_intelligence_doi_status_idx` (`doi_status`),
  KEY `publication_intelligence_final_doi_idx` (`normalised_final_primary_doi`),
  CONSTRAINT `publication_intelligence_master_fk` FOREIGN KEY (`publication_id`) REFERENCES `researcher_publications_master` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_publication_links
CREATE TABLE `researcher_publication_links` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `publication_id` bigint(20) unsigned NOT NULL,
  `source_name` varchar(50) NOT NULL,
  `source_author_id` varchar(255) DEFAULT NULL,
  `author_position` int(11) DEFAULT NULL,
  `author_name` varchar(500) DEFAULT NULL,
  `affiliation_status` varchar(50) NOT NULL DEFAULT 'needs_review',
  `match_score` decimal(5,2) DEFAULT NULL,
  `system_decision` varchar(50) NOT NULL DEFAULT 'review',
  `review_status` varchar(50) NOT NULL DEFAULT 'unreviewed',
  `reviewed_by` int(11) DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `first_linked_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_confirmed_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `researcher_publication_unique` (`borrowernumber`,`publication_id`,`source_name`),
  KEY `publication_link_borrower_idx` (`borrowernumber`),
  KEY `publication_link_publication_idx` (`publication_id`),
  KEY `publication_link_decision_idx` (`system_decision`,`review_status`),
  CONSTRAINT `publication_link_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE,
  CONSTRAINT `publication_link_master_fk` FOREIGN KEY (`publication_id`) REFERENCES `researcher_publications_master` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_publication_sources
CREATE TABLE `researcher_publication_sources` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `publication_id` bigint(20) unsigned NOT NULL,
  `source_name` varchar(50) NOT NULL,
  `source_record_id` varchar(255) NOT NULL,
  `source_url` varchar(1000) DEFAULT NULL,
  `citation_count` int(11) DEFAULT NULL,
  `raw_json` longtext DEFAULT NULL,
  `first_seen_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_synced_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `publication_source_record_unique` (`source_name`,`source_record_id`),
  KEY `publication_source_publication_idx` (`publication_id`),
  KEY `publication_source_name_idx` (`source_name`),
  CONSTRAINT `publication_source_master_fk` FOREIGN KEY (`publication_id`) REFERENCES `researcher_publications_master` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_rejoin_candidates
CREATE TABLE `researcher_rejoin_candidates` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `new_borrowernumber` int(11) NOT NULL,
  `candidate_researcher_uuid` char(36) NOT NULL,
  `orcid_match` tinyint(1) NOT NULL DEFAULT 0,
  `scopus_match` tinyint(1) NOT NULL DEFAULT 0,
  `wos_match` tinyint(1) NOT NULL DEFAULT 0,
  `email_match` tinyint(1) NOT NULL DEFAULT 0,
  `name_match` tinyint(1) NOT NULL DEFAULT 0,
  `confidence_score` decimal(5,2) NOT NULL DEFAULT 0.00,
  `evidence_json` longtext DEFAULT NULL,
  `review_status` enum('pending','confirmed','rejected') NOT NULL DEFAULT 'pending',
  `reviewed_by` int(11) DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_rejoin_candidate` (`new_borrowernumber`,`candidate_researcher_uuid`),
  KEY `idx_rrc_status` (`review_status`),
  KEY `idx_rrc_score` (`confidence_score`),
  KEY `fk_rrc_person` (`candidate_researcher_uuid`),
  CONSTRAINT `fk_rrc_person` FOREIGN KEY (`candidate_researcher_uuid`) REFERENCES `researcher_persons` (`researcher_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_source_name_variants
CREATE TABLE `researcher_source_name_variants` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) NOT NULL,
  `source_name` varchar(50) NOT NULL,
  `source_author_id` varchar(500) NOT NULL,
  `name_type` varchar(100) NOT NULL,
  `name_value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `api_json_path` varchar(1000) DEFAULT NULL,
  `extraction_method` varchar(150) DEFAULT NULL,
  `is_primary` tinyint(1) NOT NULL DEFAULT 0,
  `profile_url` varchar(1000) DEFAULT NULL,
  `first_fetched_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_fetched_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_researcher_source_exact_name` (`borrowernumber`,`source_name`,`source_author_id`,`name_value`) USING HASH,
  KEY `idx_researcher_source_names` (`borrowernumber`,`source_name`),
  KEY `idx_source_author_names` (`source_name`,`source_author_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_sync_jobs
CREATE TABLE `researcher_sync_jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) DEFAULT NULL,
  `source_name` varchar(50) NOT NULL,
  `job_type` varchar(50) NOT NULL DEFAULT 'scheduled',
  `job_status` varchar(50) NOT NULL DEFAULT 'running',
  `started_at` datetime NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  `records_found` int(11) NOT NULL DEFAULT 0,
  `records_processed` int(11) NOT NULL DEFAULT 0,
  `records_added` int(11) NOT NULL DEFAULT 0,
  `records_updated` int(11) NOT NULL DEFAULT 0,
  `records_linked` int(11) NOT NULL DEFAULT 0,
  `error_message` text DEFAULT NULL,
  `metadata_json` longtext DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `sync_job_borrower_idx` (`borrowernumber`),
  KEY `sync_job_source_idx` (`source_name`),
  KEY `sync_job_status_idx` (`job_status`),
  KEY `sync_job_started_idx` (`started_at`),
  CONSTRAINT `sync_job_borrower_fk` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- researcher_account_history_v
CREATE ALGORITHM=UNDEFINED SQL SECURITY DEFINER VIEW `researcher_account_history_v` AS select `p`.`researcher_uuid` AS `researcher_uuid`,`p`.`canonical_name` AS `canonical_name`,`p`.`lifecycle_status` AS `lifecycle_status`,`l`.`id` AS `patron_link_id`,`l`.`borrowernumber` AS `borrowernumber`,`l`.`cardnumber` AS `cardnumber`,`l`.`employee_id` AS `employee_id`,`l`.`institutional_email` AS `institutional_email`,`l`.`link_status` AS `link_status`,`l`.`valid_from` AS `valid_from`,`l`.`valid_to` AS `valid_to`,`l`.`link_method` AS `link_method`,`l`.`confidence_score` AS `confidence_score`,case when `l`.`link_status` = 'current' then 1 else 0 end AS `is_current_account` from (`researcher_persons` `p` join `researcher_patron_links` `l` on(`l`.`researcher_uuid` = `p`.`researcher_uuid`));

-- researcher_current_identity_v
CREATE ALGORITHM=UNDEFINED SQL SECURITY DEFINER VIEW `researcher_current_identity_v` AS select `p`.`researcher_uuid` AS `researcher_uuid`,`p`.`canonical_name` AS `canonical_name`,`p`.`lifecycle_status` AS `lifecycle_status`,`p`.`verification_status` AS `verification_status`,`l`.`borrowernumber` AS `current_borrowernumber`,`l`.`cardnumber` AS `current_cardnumber`,`l`.`employee_id` AS `current_employee_id`,`l`.`institutional_email` AS `current_email`,`l`.`valid_from` AS `current_valid_from`,`l`.`link_method` AS `link_method`,`l`.`confidence_score` AS `confidence_score` from (`researcher_persons` `p` left join `researcher_patron_links` `l` on(`l`.`researcher_uuid` = `p`.`researcher_uuid` and `l`.`link_status` = 'current'));

-- researcher_publication_identity_v
CREATE ALGORITHM=UNDEFINED SQL SECURITY DEFINER VIEW `researcher_publication_identity_v` AS select `p`.`researcher_uuid` AS `researcher_uuid`,`p`.`canonical_name` AS `canonical_name`,`rpl`.`id` AS `publication_link_id`,`rpl`.`borrowernumber` AS `source_borrowernumber`,`current_link`.`borrowernumber` AS `current_borrowernumber`,`rpl`.`publication_id` AS `publication_id`,`rpl`.`source_name` AS `source_name`,`rpl`.`source_author_id` AS `source_author_id`,`rpl`.`author_position` AS `author_position`,`rpl`.`author_name` AS `author_name`,`rpl`.`affiliation_status` AS `affiliation_status`,`rpl`.`match_score` AS `match_score`,`rpl`.`system_decision` AS `system_decision`,`rpl`.`review_status` AS `review_status`,`rpl`.`first_linked_at` AS `first_linked_at`,`rpl`.`last_confirmed_at` AS `last_confirmed_at` from (((`researcher_publication_links` `rpl` join `researcher_patron_links` `historical_link` on(`historical_link`.`borrowernumber` = `rpl`.`borrowernumber`)) join `researcher_persons` `p` on(`p`.`researcher_uuid` = `historical_link`.`researcher_uuid`)) left join `researcher_patron_links` `current_link` on(`current_link`.`researcher_uuid` = `p`.`researcher_uuid` and `current_link`.`link_status` = 'current'));

SET FOREIGN_KEY_CHECKS=1;
