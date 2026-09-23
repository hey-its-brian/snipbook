import Foundation

/// Starter snippets written the first time the library folder is created.
enum SeedLibrary {
    private struct Seed {
        let folder: String
        let file: String
        var locked = false
        let body: String
    }

    static func install(at root: URL) {
        let fm = FileManager.default
        for seed in seeds {
            let dir = root.appendingPathComponent(seed.folder, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(seed.file)
            try? seed.body.write(to: url, atomically: true, encoding: .utf8)
            if seed.locked { try? fm.setAttributes([.immutable: true], ofItemAtPath: url.path) }
        }
    }

    private static let seeds: [Seed] = [
        Seed(folder: "Ruby & Rails", file: "Service object.rb", body: #"""
        # app/services/application_service.rb
        class ApplicationService
          def self.call(...) = new(...).call
        end

        class Users::Deactivate < ApplicationService
          def initialize(user, reason:)
            @user = user
            @reason = reason
          end

          def call
            User.transaction do
              @user.update!(active: false, deactivated_at: Time.current)
              AuditLog.create!(user: @user, action: "deactivate", note: @reason)
            end
          end
        end

        # Users::Deactivate.call(user, reason: "requested")
        """#),
        Seed(folder: "Ruby & Rails", file: "Model scopes and enum.rb", body: #"""
        class Order < ApplicationRecord
          belongs_to :customer
          has_many :line_items, dependent: :destroy

          enum :status, { pending: 0, paid: 1, shipped: 2, cancelled: 3 }, default: :pending

          scope :recent, -> { where(created_at: 30.days.ago..) }
          scope :for_customer, ->(customer) { where(customer:) }
          scope :big, ->(min = 100_00) { where("total_cents >= ?", min) }

          validates :total_cents, numericality: { greater_than_or_equal_to: 0 }
        end
        """#),
        Seed(folder: "Ruby & Rails", file: "Add index concurrently migration.rb", body: #"""
        class AddIndexOnOrdersCustomerId < ActiveRecord::Migration[7.1]
          disable_ddl_transaction!

          def change
            add_index :orders, :customer_id, algorithm: :concurrently, if_not_exists: true
          end
        end
        """#),
        Seed(folder: "Ruby & Rails", file: "Form partial.erb", body: #"""
        <%= form_with model: @post, class: "stack" do |f| %>
          <% if @post.errors.any? %>
            <div class="errors">
              <% @post.errors.full_messages.each do |msg| %>
                <p><%= msg %></p>
              <% end %>
            </div>
          <% end %>

          <%= f.label :title %>
          <%= f.text_field :title, required: true %>

          <%= f.label :body %>
          <%= f.text_area :body, rows: 8 %>

          <%= f.submit %>
        <% end %>
        """#),

        Seed(folder: "Bash", file: "Strict mode script header.sh", locked: true, body: #"""
        #!/usr/bin/env bash
        # Fail fast: exit on error, unset vars, and failures inside pipes.
        set -euo pipefail
        IFS=$'\n\t'

        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

        log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
        die()  { log "ERROR: $*"; exit 1; }

        trap 'die "failed at line $LINENO"' ERR

        main() {
          [[ $# -ge 1 ]] || die "usage: $(basename "$0") <arg>"
          log "running in $SCRIPT_DIR with $1"
        }

        main "$@"
        """#),
        Seed(folder: "Bash", file: "Find and replace across files.sh", body: #"""
        # Preview matches first
        rg -n 'old_name' --glob '!vendor/**'

        # Replace in place (macOS sed needs the empty '' after -i)
        rg -l 'old_name' --glob '!vendor/**' | xargs sed -i '' 's/old_name/new_name/g'
        """#),
        Seed(folder: "Bash", file: "Serial monitor for ESP32.sh", body: #"""
        # List USB serial ports
        ls /dev/cu.usb*

        # Open a monitor at 115200 baud (Ctrl-A then K to quit)
        screen /dev/cu.usbserial-0001 115200

        # PlatformIO alternative with filters
        pio device monitor -b 115200 -f esp32_exception_decoder
        """#),

        Seed(folder: "SQL", file: "Find duplicate rows.sql", body: #"""
        SELECT email, COUNT(*) AS copies, ARRAY_AGG(id ORDER BY id) AS ids
        FROM users
        GROUP BY email
        HAVING COUNT(*) > 1
        ORDER BY copies DESC;
        """#),
        Seed(folder: "SQL", file: "Postgres table sizes.sql", body: #"""
        SELECT relname AS table,
               pg_size_pretty(pg_total_relation_size(relid)) AS total,
               pg_size_pretty(pg_relation_size(relid))       AS data,
               n_live_tup                                    AS rows
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(relid) DESC
        LIMIT 20;
        """#),
        Seed(folder: "SQL", file: "Latest row per group.sql", body: #"""
        -- Most recent order for every customer
        SELECT DISTINCT ON (customer_id) *
        FROM orders
        ORDER BY customer_id, created_at DESC;

        -- Portable version with a window function
        SELECT *
        FROM (
          SELECT o.*, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at DESC) AS rn
          FROM orders o
        ) ranked
        WHERE rn = 1;
        """#),

        Seed(folder: "JavaScript", file: "Debounce.js", body: #"""
        export function debounce(fn, wait = 250) {
          let timer;
          return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn(...args), wait);
          };
        }

        // input.addEventListener("input", debounce(e => search(e.target.value), 300));
        """#),
        Seed(folder: "JavaScript", file: "Fetch JSON with timeout.js", body: #"""
        export async function fetchJSON(url, { timeout = 8000, ...options } = {}) {
          const res = await fetch(url, {
            ...options,
            signal: AbortSignal.timeout(timeout),
            headers: { Accept: "application/json", ...options.headers },
          });
          if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
          return res.json();
        }
        """#),
        Seed(folder: "JavaScript", file: "Stimulus controller.js", body: #"""
        // app/javascript/controllers/clipboard_controller.js
        import { Controller } from "@hotwired/stimulus"

        export default class extends Controller {
          static targets = ["source", "button"]

          async copy() {
            await navigator.clipboard.writeText(this.sourceTarget.value)
            this.buttonTarget.textContent = "Copied!"
            setTimeout(() => (this.buttonTarget.textContent = "Copy"), 1500)
          }
        }
        """#),

        Seed(folder: "HTML & CSS", file: "HTML boilerplate.html", body: #"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Page title</title>
          <link rel="stylesheet" href="style.css">
        </head>
        <body>
          <main>
            <h1>Hello</h1>
          </main>
          <script src="app.js" defer></script>
        </body>
        </html>
        """#),
        Seed(folder: "HTML & CSS", file: "Center anything.css", body: #"""
        /* Grid: one line, centers both axes */
        .center {
          display: grid;
          place-items: center;
          min-height: 100dvh;
        }

        /* Flex version */
        .center-flex {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        """#),
        Seed(folder: "HTML & CSS", file: "Light and dark theme tokens.css", body: #"""
        :root {
          color-scheme: light dark;
          --bg: #ffffff;
          --fg: #1d1d1f;
          --accent: #0a84ff;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #1c1c1e;
            --fg: #f5f5f7;
          }
        }

        body {
          background: var(--bg);
          color: var(--fg);
          font: 16px/1.5 system-ui, sans-serif;
        }
        """#),

        Seed(folder: "Python", file: "CLI skeleton.py", body: #"""
        #!/usr/bin/env python3
        import argparse
        import logging
        from pathlib import Path

        log = logging.getLogger(__name__)


        def main() -> int:
            parser = argparse.ArgumentParser(description="Describe the tool.")
            parser.add_argument("path", type=Path)
            parser.add_argument("-v", "--verbose", action="store_true")
            args = parser.parse_args()

            logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                                format="%(levelname)s %(message)s")
            if not args.path.exists():
                log.error("%s does not exist", args.path)
                return 1
            log.info("processing %s", args.path)
            return 0


        if __name__ == "__main__":
            raise SystemExit(main())
        """#),

        Seed(folder: "Arduino & C++", file: "Non-blocking timer.ino", body: #"""
        // Run work on an interval without delay() blocking the loop.
        const unsigned long INTERVAL_MS = 1000;
        unsigned long lastRun = 0;

        void setup() {
          Serial.begin(115200);
        }

        void loop() {
          unsigned long now = millis();
          if (now - lastRun >= INTERVAL_MS) {  // safe across millis() rollover
            lastRun = now;
            Serial.printf("tick %lu\n", now);
          }
        }
        """#),
        Seed(folder: "Arduino & C++", file: "ESP32 WiFi connect.ino", body: #"""
        #include <WiFi.h>

        const char* SSID = "your-ssid";
        const char* PASS = "your-password";

        bool connectWiFi(uint32_t timeoutMs = 15000) {
          WiFi.mode(WIFI_STA);
          WiFi.begin(SSID, PASS);
          uint32_t start = millis();
          while (WiFi.status() != WL_CONNECTED) {
            if (millis() - start > timeoutMs) return false;
            delay(250);
          }
          Serial.printf("Connected: %s\n", WiFi.localIP().toString().c_str());
          return true;
        }
        """#),
        Seed(folder: "Arduino & C++", file: "platformio.ini", body: #"""
        [env:esp32dev]
        platform = espressif32
        board = esp32dev
        framework = arduino
        monitor_speed = 115200
        monitor_filters = esp32_exception_decoder
        build_flags = -DCORE_DEBUG_LEVEL=3
        lib_deps =
            bodmer/TFT_eSPI
        """#),

        Seed(folder: "Config", file: "GitHub Actions Ruby CI.yml", body: #"""
        name: CI
        on: [push, pull_request]

        jobs:
          test:
            runs-on: ubuntu-latest
            services:
              postgres:
                image: postgres:16
                env:
                  POSTGRES_PASSWORD: postgres
                ports: ["5432:5432"]
            steps:
              - uses: actions/checkout@v4
              - uses: ruby/setup-ruby@v1
                with:
                  bundler-cache: true
              - run: bin/rails db:prepare
                env:
                  DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
              - run: bin/rails test
        """#),
        Seed(folder: "Config", file: "VS Code settings.json", body: #"""
        {
          "editor.formatOnSave": true,
          "editor.rulers": [100],
          "files.trimTrailingWhitespace": true,
          "[ruby]": { "editor.tabSize": 2 },
          "[python]": { "editor.tabSize": 4 }
        }
        """#),
    ]
}
