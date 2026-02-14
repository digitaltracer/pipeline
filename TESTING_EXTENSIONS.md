# Testing Pipeline Browser Extensions

This guide walks you through setting up and testing the Pipeline browser extensions for **Safari** and **Google Chrome**. The extensions let you save job postings directly from job sites into the Pipeline app with one click.

---

## Before You Start

Make sure you have:

- The **Pipeline** app built and running on your Mac (open the project in Xcode, press the Play button)
- A job board account you can browse (LinkedIn, Indeed, Glassdoor, or Naukri)

---

## Option A: Safari Extension

### Step 1 — Enable the extension

1. Open **Safari**
2. In the menu bar, go to **Safari > Settings** (or press `Cmd + ,`)
3. Click the **Extensions** tab
4. Find **"Pipeline"** in the list on the left and **check the box** to enable it
5. You may see a prompt asking to allow the extension — click **Allow**

> If you don't see Pipeline in the list, make sure the app has been built and run at least once from Xcode.

### Step 2 — Allow access to job sites

1. Still in Safari Settings > Extensions, click on **Pipeline**
2. Under "Permissions", make sure it has access to the job sites you want to use
3. You can choose **"Always Allow on Every Website"** or add specific sites like `linkedin.com`, `indeed.com`, etc.

### Step 3 — Save a job posting

1. Go to a job posting on any supported site:
   - **LinkedIn** — open any job listing page
   - **Indeed** — open any job details page
   - **Glassdoor** — open any job listing
   - **Naukri** — open any job listing
   - Any other job page will also work (with basic extraction)

2. Click the **Pipeline icon** in the Safari toolbar (it appears near the address bar)

3. A small popup will appear showing:
   - **Title** — the job title
   - **Company** — the company name
   - **Location** — where the job is
   - **Description** — a preview of the job description

4. Review the extracted information, then click **"Save to Pipeline"**

5. You should see a green **"Saved to Pipeline!"** message

6. Open the **Pipeline app** — the job should appear in your application list with status "Saved"

---

## Option B: Chrome Extension

Setting up the Chrome extension requires a few extra steps since it's not yet published to the Chrome Web Store.

### Step 1 — Load the extension in Chrome

1. Open **Google Chrome**
2. Type `chrome://extensions` in the address bar and press Enter
3. Turn on **"Developer mode"** using the toggle in the top-right corner
4. Click **"Load unpacked"** in the top-left
5. Navigate to the Pipeline project folder and select the **`ChromeExtension`** folder
6. The Pipeline extension should appear in your extensions list

### Step 2 — Note the Extension ID

After loading, Chrome will show the extension with a long ID underneath (it looks like random letters, e.g., `abcdefghijklmnopqrstuvwx`). **Copy this ID** — you'll need it in the next step.

### Step 3 — Install the native messaging host

The Chrome extension needs a small helper program to communicate with the Pipeline app. To set this up:

1. Open the **Terminal** app (you can find it in Applications > Utilities, or search for "Terminal" in Spotlight)

2. Type or paste the following commands, replacing `YOUR_EXTENSION_ID` with the ID you copied in Step 2:

   ```
   cd /path/to/pipeline/ChromeExtension
   ./install_host.sh YOUR_EXTENSION_ID
   ```

   For example, if your project is on the Desktop:
   ```
   cd ~/Desktop/pipeline/ChromeExtension
   ./install_host.sh abcdefghijklmnopqrstuvwx
   ```

3. You should see a message saying the host was installed successfully

> **Note:** The Pipeline app must be built from Xcode at least once for the native host to exist.

### Step 4 — Pin the extension (optional but recommended)

1. Click the **puzzle piece icon** in Chrome's toolbar (top-right)
2. Find **"Pipeline — Job Application Tracker"**
3. Click the **pin icon** next to it so it stays visible in your toolbar

### Step 5 — Save a job posting

1. Go to a job posting on any supported site (same list as Safari above)

2. Click the **Pipeline icon** (blue "P") in the Chrome toolbar

3. The popup will show the extracted job details — review them

4. Click **"Save to Pipeline"**

5. You should see a green **"Saved to Pipeline!"** confirmation

6. Open the **Pipeline app** to verify the job appears in your list

---

## Supported Job Sites

The extensions work best on these sites with tailored extraction:

| Site | What Gets Extracted |
|------|-------------------|
| **LinkedIn** | Job title, company, location, full description |
| **Indeed** | Job title, company, location, full description |
| **Glassdoor** | Job title, company, location, full description |
| **Naukri** | Job title, company, location, full description |
| **Greenhouse** | Job details from posting page |
| **Lever** | Job details from posting page |
| **Workday** | Job details from posting page |
| **Any other site** | Best-effort extraction from page content |

---

## What to Test

Here's a checklist of things to verify when testing:

- [ ] Extension icon appears in the browser toolbar
- [ ] Clicking the icon on a job page shows extracted data in the popup
- [ ] Title, company, and location are correctly extracted
- [ ] Description preview shows relevant content (not navigation menus or ads)
- [ ] Clicking "Save to Pipeline" shows a success message
- [ ] The saved job appears in the Pipeline app with correct details
- [ ] Saving the **same job twice** shows a duplicate warning
- [ ] The extension works on at least 2 different job sites
- [ ] Clicking the extension on a non-job page shows "No job posting detected"

---

## Troubleshooting

### "No job posting detected"
- Make sure you're on an actual job listing page, not a search results page
- Try refreshing the page and clicking the extension again

### Safari extension doesn't appear
- Make sure the Pipeline app has been built and run from Xcode at least once
- Check Safari > Settings > Extensions and ensure Pipeline is enabled
- Restart Safari

### Chrome extension says "Cannot connect to native host"
- Make sure you ran the `install_host.sh` script (Step 3 in Chrome setup)
- Make sure you used the correct Extension ID
- Make sure the Pipeline app has been built from Xcode (the native host binary needs to exist)
- Try restarting Chrome

### Job data looks incomplete or wrong
- Some job sites load content dynamically — try waiting a few seconds for the page to fully load before clicking the extension
- The extension extracts what's visible on the page, so if the job description is behind a "Show more" button, click that first

### Saved job doesn't appear in Pipeline
- Make sure the Pipeline app is running
- Try quitting and reopening the Pipeline app
- Check that both the app and extension are using the same data store (they share data automatically)
