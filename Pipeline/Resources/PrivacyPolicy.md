# Pipeline Privacy Policy

Last updated: March 14, 2026

## Overview

Pipeline stores and organizes job-search data on your device. This policy explains what the app stores, when data may sync with iCloud, how AI features use your data, and what diagnostics the app keeps.

## Data Stored in Pipeline

Pipeline can store:

- Job applications, company names, role titles, locations, status history, tasks, reminders, interview logs, and notes
- Contact details for recruiters, interviewers, and other people you link to applications
- Compensation details, company research notes, and analytics records
- Resume content, resume snapshots, and generated tailoring suggestions
- Managed attachments such as resumes, offer letters, PDFs, images, links, and note attachments

This data is stored locally in Pipeline's app container. Managed file attachments are stored in Pipeline-controlled storage rather than inside the system Keychain.

## iCloud Sync

If you enable iCloud Sync, Pipeline stores supported app data in your private iCloud container so it can sync across your devices. If iCloud Sync is off, Pipeline keeps app data local to the current device.

Turning iCloud Sync off does not automatically delete data that was previously synced. Existing synced data may remain in iCloud until you remove it through Apple-managed settings or overwrite it with later changes.

## API Keys

Pipeline stores AI provider API keys in your system Keychain. API keys are not stored in plain text inside Pipeline's regular app data store.

Pipeline does not currently enforce API key rotation schedules, expiry reminders, or automatic revocation. You are responsible for rotating or removing keys through the provider you use.

## Google Calendar Integration

If you connect Google Calendar, Pipeline stores Google sign-in credentials in your system Keychain and keeps imported calendar metadata, linked interview sync state, and saved interview brief snapshots in Pipeline's regular app data store so you can review, sync, and reopen interview prep context from Google Calendar.

Pipeline requests read access to your selected Google calendars and write access for interview events. It can read calendar lists and event details from the calendars you enable, and it can create, update, or delete Pipeline-managed interview and prep events in the writable calendar you choose.

Disconnecting Google Calendar removes saved Google credentials from Keychain. Imported application activities, linked interview metadata, and review history remain in Pipeline unless you delete them separately.

## LinkedIn CSV Import

If you import a LinkedIn connections CSV, Pipeline stores the imported network rows in its regular app data store so it can suggest referral opportunities, promote useful rows into saved contacts, and track referral outreach history.

Imported LinkedIn network data may include names, company names, job titles, email addresses, profile URLs, and imported connection metadata such as when the connection was created if that information is present in the CSV.

Deleting the imported LinkedIn network from Integrations removes the stored imported rows and import-batch metadata. Any contacts, application links, activities, or referral-attempt history you created from that imported data remain in Pipeline unless you delete them separately.

## AI Features and Provider Requests

When you use AI-powered features, Pipeline sends relevant content to the AI provider you selected. Depending on the feature, this may include:

- Job posting URLs and extracted job descriptions
- Resume JSON or tailored resume content
- Notes or instructions you enter to generate drafts or patch revisions
- Company research prompts and related source content
- Interview notes, interview history, and related company or role context when you generate interview prep or saved interview brief snapshots

These requests are sent directly to the provider you configured, such as OpenAI, Anthropic, or Google Gemini. Their handling of that data is governed by their own terms and privacy policies.

## Diagnostics and Logging

Pipeline keeps lightweight diagnostics to help identify request failures and performance issues. These diagnostics may include provider names, model names, HTTP status codes, token counts, byte counts, and sanitized host or path information.

Pipeline is designed not to log sensitive job-search content, raw job descriptions, resume bodies, notes, prompts, or full AI responses in production builds.

## App Lock

If you enable App Lock, Pipeline requires device authentication after the app leaves the foreground. App Lock uses Face ID, Touch ID, or your device passcode through Apple's LocalAuthentication framework.

App Lock helps protect on-screen access to your data, but it does not add a separate encryption layer to Pipeline's stored files.

## Data Deletion

You can delete applications, contacts, tasks, activities, and attachments from inside Pipeline. Deleting an attachment that Pipeline manages removes the managed file copy stored for that attachment.

Pipeline does not currently provide a one-click export or full-account deletion workflow. If iCloud Sync is enabled, Apple may retain synced copies according to its own systems until you remove that data through Apple-managed storage settings.

## Contact

If you need support or want to report a privacy concern, use the support link in Settings.
