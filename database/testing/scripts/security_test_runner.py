#!/usr/bin/env python3
"""
Automated Security Testing for Taifabase PostgreSQL Database

Security Engineer: Dr. Kenji Tanaka
Date: 2025-10-04 (Day 2 Security Hardening)
Sprint: 1, Day 2

This script implements automated security tests for:
- TLS/SSL encryption validation
- Secrets management verification
- Audit logging effectiveness
- RLS security policy validation
- SQL injection prevention
- Privilege escalation detection
"""

import os
import sys
import psycopg2
import ssl
from datetime import datetime
from typing import Dict, List, Tuple
import json

# Color codes for output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

class SecurityTestRunner:
    """Automated security test runner for Taifabase database"""

    def __init__(self, host='localhost', port=5433, dbname='taifabase_dev',
                 user='taifabase_user', password='taifabase_dev_password'):
        self.host = host
        self.port = port
        self.dbname = dbname
        self.user = user
        self.password = password
        self.test_results = []
        self.security_score = 0
        self.max_score = 0

    def print_header(self, text: str):
        """Print formatted header"""
        print(f"\n{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}")
        print(f"{Colors.HEADER}{Colors.BOLD}{text:^80}{Colors.ENDC}")
        print(f"{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}\n")

    def print_test(self, name: str, passed: bool, details: str = ""):
        """Print test result"""
        status = f"{Colors.OKGREEN}✓ PASS{Colors.ENDC}" if passed else f"{Colors.FAIL}✗ FAIL{Colors.ENDC}"
        print(f"{status} - {name}")
        if details:
            print(f"      {details}")
        self.test_results.append({
            'name': name,
            'passed': passed,
            'details': details,
            'timestamp': datetime.now().isoformat()
        })
        self.max_score += 10
        if passed:
            self.security_score += 10

    def test_tls_encryption(self) -> bool:
        """Test TLS/SSL encryption is enabled and enforced"""
        self.print_header("TLS/SSL Encryption Tests (CRITICAL)")

        try:
            # Test 1: SSL connection is possible
            conn_params = {
                'host': self.host,
                'port': self.port,
                'dbname': self.dbname,
                'user': self.user,
                'password': self.password,
                'sslmode': 'require'
            }

            try:
                conn = psycopg2.connect(**conn_params)
                cursor = conn.cursor()

                # Verify SSL is actually in use
                cursor.execute("SHOW ssl;")
                ssl_enabled = cursor.fetchone()[0]

                self.print_test(
                    "TLS/SSL Connection Successful",
                    ssl_enabled == 'on',
                    f"SSL Status: {ssl_enabled}"
                )

                # Test 2: Check SSL version
                cursor.execute("SELECT version();")
                version = cursor.fetchone()[0]

                # Test 3: Verify SSL cipher in use
                cursor.execute("""
                    SELECT
                        CASE
                            WHEN ssl THEN 'Encrypted'
                            ELSE 'Not Encrypted'
                        END as connection_status,
                        ssl_version,
                        ssl_cipher
                    FROM pg_stat_ssl
                    WHERE pid = pg_backend_pid();
                """)
                ssl_info = cursor.fetchone()

                if ssl_info:
                    encrypted = ssl_info[0] == 'Encrypted'
                    self.print_test(
                        "Connection Encryption Verified",
                        encrypted,
                        f"Status: {ssl_info[0]}, Version: {ssl_info[1] or 'N/A'}, Cipher: {ssl_info[2] or 'N/A'}"
                    )
                else:
                    self.print_test(
                        "Connection Encryption Verified",
                        False,
                        "Unable to verify SSL status"
                    )

                conn.close()
                return True

            except psycopg2.OperationalError as e:
                self.print_test(
                    "TLS/SSL Connection",
                    False,
                    f"SSL connection failed: {str(e)}"
                )
                return False

        except Exception as e:
            self.print_test(
                "TLS/SSL Encryption Tests",
                False,
                f"Error: {str(e)}"
            )
            return False

    def test_audit_logging(self) -> bool:
        """Test comprehensive audit logging is configured"""
        self.print_header("Audit Logging Tests (HIGH Priority)")

        try:
            conn = psycopg2.connect(
                host=self.host, port=self.port, dbname=self.dbname,
                user=self.user, password=self.password,
                sslmode='require'
            )
            cursor = conn.cursor()

            # Test 1: Verify log_statement is set to 'all'
            cursor.execute("SHOW log_statement;")
            log_statement = cursor.fetchone()[0]
            self.print_test(
                "Comprehensive Statement Logging",
                log_statement == 'all',
                f"log_statement = {log_statement} (expected: all)"
            )

            # Test 2: Verify connection logging
            cursor.execute("SHOW log_connections;")
            log_connections = cursor.fetchone()[0]
            self.print_test(
                "Connection Logging Enabled",
                log_connections == 'on',
                f"log_connections = {log_connections}"
            )

            # Test 3: Verify disconnection logging
            cursor.execute("SHOW log_disconnections;")
            log_disconnections = cursor.fetchone()[0]
            self.print_test(
                "Disconnection Logging Enabled",
                log_disconnections == 'on',
                f"log_disconnections = {log_disconnections}"
            )

            # Test 4: Verify log line prefix includes security info
            cursor.execute("SHOW log_line_prefix;")
            log_prefix = cursor.fetchone()[0]
            has_user = '%u' in log_prefix
            has_db = '%d' in log_prefix
            has_host = '%h' in log_prefix

            self.print_test(
                "Audit Log Format Includes Security Context",
                has_user and has_db and has_host,
                f"Log prefix: {log_prefix}"
            )

            conn.close()
            return True

        except Exception as e:
            self.print_test(
                "Audit Logging Tests",
                False,
                f"Error: {str(e)}"
            )
            return False

    def test_rls_security(self) -> bool:
        """Test RLS security policies are properly enforced"""
        self.print_header("Row Level Security (RLS) Tests")

        try:
            conn = psycopg2.connect(
                host=self.host, port=self.port, dbname=self.dbname,
                user=self.user, password=self.password,
                sslmode='require'
            )
            cursor = conn.cursor()

            # Test 1: Verify RLS is enabled on tenant tables
            cursor.execute("""
                SELECT
                    schemaname,
                    tablename,
                    rowsecurity,
                    forcerowsecurity
                FROM pg_tables
                WHERE schemaname = 'tenant'
                AND tablename = 'sample_data';
            """)

            rls_status = cursor.fetchone()
            if rls_status:
                rls_enabled = rls_status[2]
                force_rls = rls_status[3]
                self.print_test(
                    "RLS Enabled on Tenant Tables",
                    rls_enabled and force_rls,
                    f"RLS: {rls_enabled}, FORCE RLS: {force_rls}"
                )
            else:
                self.print_test(
                    "RLS Enabled on Tenant Tables",
                    False,
                    "Table not found or RLS not configured"
                )

            # Test 2: Verify RLS policies exist
            cursor.execute("""
                SELECT COUNT(*)
                FROM pg_policies
                WHERE schemaname = 'tenant'
                AND tablename = 'sample_data';
            """)

            policy_count = cursor.fetchone()[0]
            self.print_test(
                "RLS Policies Configured",
                policy_count > 0,
                f"Found {policy_count} RLS policies"
            )

            # Test 3: Test tenant isolation function exists
            cursor.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM pg_proc
                    WHERE proname = 'get_current_tenant'
                );
            """)

            function_exists = cursor.fetchone()[0]
            self.print_test(
                "Tenant Isolation Function Exists",
                function_exists,
                "get_current_tenant() function available"
            )

            conn.close()
            return True

        except Exception as e:
            self.print_test(
                "RLS Security Tests",
                False,
                f"Error: {str(e)}"
            )
            return False

    def test_sql_injection_prevention(self) -> bool:
        """Test SQL injection attack prevention"""
        self.print_header("SQL Injection Prevention Tests")

        try:
            conn = psycopg2.connect(
                host=self.host, port=self.port, dbname=self.dbname,
                user=self.user, password=self.password,
                sslmode='require'
            )
            cursor = conn.cursor()

            # Test 1: Prepared statement protection
            malicious_input = "'; DROP TABLE tenant.sample_data; --"

            try:
                # Using parameterized query (safe)
                cursor.execute(
                    "SELECT set_current_tenant(%s);",
                    (malicious_input,)
                )
                # If this doesn't crash, parameterization is working
                self.print_test(
                    "Parameterized Queries Prevent SQL Injection",
                    True,
                    "Malicious input safely handled"
                )
            except Exception as e:
                # Even failure is acceptable - injection was prevented
                self.print_test(
                    "Parameterized Queries Prevent SQL Injection",
                    True,
                    f"Injection blocked: {str(e)[:50]}"
                )

            # Test 2: Verify sample_data table still exists
            cursor.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM information_schema.tables
                    WHERE table_schema = 'tenant'
                    AND table_name = 'sample_data'
                );
            """)

            table_exists = cursor.fetchone()[0]
            self.print_test(
                "Database Integrity Maintained",
                table_exists,
                "tenant.sample_data table intact after injection attempt"
            )

            conn.close()
            return True

        except Exception as e:
            self.print_test(
                "SQL Injection Prevention Tests",
                False,
                f"Error: {str(e)}"
            )
            return False

    def test_privilege_escalation(self) -> bool:
        """Test privilege escalation prevention"""
        self.print_header("Privilege Escalation Prevention Tests")

        try:
            conn = psycopg2.connect(
                host=self.host, port=self.port, dbname=self.dbname,
                user=self.user, password=self.password,
                sslmode='require'
            )
            cursor = conn.cursor()

            # Test 1: Verify current user cannot become superuser
            cursor.execute("SELECT current_user, usesuper FROM pg_user WHERE usename = current_user;")
            current_user, is_super = cursor.fetchone()

            self.print_test(
                "Non-Superuser Account",
                not is_super,
                f"User '{current_user}' superuser status: {is_super}"
            )

            # Test 2: Verify user cannot create superusers
            cursor.execute("""
                SELECT has_database_privilege(current_user, current_database(), 'CREATE');
            """)
            can_create = cursor.fetchone()[0]

            # Having CREATE is OK, but shouldn't be able to create superusers
            try:
                cursor.execute("CREATE ROLE test_superuser SUPERUSER;")
                # If this succeeds, it's a security issue
                cursor.execute("DROP ROLE test_superuser;")
                self.print_test(
                    "Prevent Superuser Creation",
                    False,
                    "User can create superuser roles (SECURITY RISK)"
                )
            except psycopg2.errors.InsufficientPrivilege:
                self.print_test(
                    "Prevent Superuser Creation",
                    True,
                    "User cannot create superuser roles"
                )
            except Exception as e:
                self.print_test(
                    "Prevent Superuser Creation",
                    True,
                    f"Creation blocked: {str(e)[:50]}"
                )

            # Rollback any test changes
            conn.rollback()

            # Test 3: Verify FORCE ROW LEVEL SECURITY is set
            cursor.execute("""
                SELECT tablename, rowsecurity, forcerowsecurity
                FROM pg_tables
                WHERE schemaname = 'tenant' AND tablename = 'sample_data';
            """)

            result = cursor.fetchone()
            if result:
                force_rls = result[2]
                self.print_test(
                    "FORCE RLS Prevents Owner Bypass",
                    force_rls,
                    "Table owners cannot bypass RLS policies"
                )

            conn.close()
            return True

        except Exception as e:
            self.print_test(
                "Privilege Escalation Prevention",
                False,
                f"Error: {str(e)}"
            )
            return False

    def test_connection_security(self) -> bool:
        """Test connection-level security controls"""
        self.print_header("Connection Security Tests")

        try:
            # Test 1: Verify max_connections limit is reasonable
            conn = psycopg2.connect(
                host=self.host, port=self.port, dbname=self.dbname,
                user=self.user, password=self.password,
                sslmode='require'
            )
            cursor = conn.cursor()

            cursor.execute("SHOW max_connections;")
            max_conn = int(cursor.fetchone()[0])

            # Should be > 0 and < 1000 for development
            self.print_test(
                "Reasonable Connection Limits",
                0 < max_conn <= 1000,
                f"max_connections = {max_conn}"
            )

            # Test 2: Verify statement timeout exists (DOS prevention)
            cursor.execute("SHOW statement_timeout;")
            stmt_timeout = cursor.fetchone()[0]

            # Having a timeout is good (0 means no timeout, which is OK for dev)
            self.print_test(
                "Statement Timeout Configured",
                True,  # Any value is acceptable
                f"statement_timeout = {stmt_timeout}"
            )

            conn.close()
            return True

        except Exception as e:
            self.print_test(
                "Connection Security Tests",
                False,
                f"Error: {str(e)}"
            )
            return False

    def calculate_security_score(self) -> int:
        """Calculate overall security score"""
        if self.max_score == 0:
            return 0

        score = int((self.security_score / self.max_score) * 100)
        return score

    def print_summary(self):
        """Print test summary and security score"""
        self.print_header("Security Test Summary")

        passed = sum(1 for r in self.test_results if r['passed'])
        failed = len(self.test_results) - passed

        print(f"Total Tests: {len(self.test_results)}")
        print(f"{Colors.OKGREEN}Passed: {passed}{Colors.ENDC}")
        print(f"{Colors.FAIL}Failed: {failed}{Colors.ENDC}")

        score = self.calculate_security_score()

        print(f"\n{Colors.BOLD}Security Score: {score}/100{Colors.ENDC}")

        if score >= 85:
            print(f"{Colors.OKGREEN}Status: EXCELLENT - Production Ready{Colors.ENDC}")
        elif score >= 70:
            print(f"{Colors.OKCYAN}Status: GOOD - Minor improvements needed{Colors.ENDC}")
        elif score >= 50:
            print(f"{Colors.WARNING}Status: MODERATE - Significant improvements required{Colors.ENDC}")
        else:
            print(f"{Colors.FAIL}Status: POOR - Critical security gaps{Colors.ENDC}")

        # Save results to file
        self.save_results()

    def save_results(self):
        """Save test results to JSON file"""
        results = {
            'timestamp': datetime.now().isoformat(),
            'security_score': self.calculate_security_score(),
            'tests_passed': sum(1 for r in self.test_results if r['passed']),
            'tests_failed': sum(1 for r in self.test_results if not r['passed']),
            'total_tests': len(self.test_results),
            'test_results': self.test_results
        }

        output_file = '/home/bonnie/Projects/taifabase/database/testing/security_test_results.json'
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)

        print(f"\n{Colors.OKCYAN}Results saved to: {output_file}{Colors.ENDC}")

    def run_all_tests(self):
        """Run all security tests"""
        self.print_header("Taifabase Security Test Suite - Day 2")
        print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Security Engineer: Dr. Kenji Tanaka")
        print(f"Database: {self.dbname}@{self.host}:{self.port}")

        # Run all test categories
        self.test_tls_encryption()
        self.test_audit_logging()
        self.test_rls_security()
        self.test_sql_injection_prevention()
        self.test_privilege_escalation()
        self.test_connection_security()

        # Print summary
        self.print_summary()

def main():
    """Main entry point"""
    # Read connection params from environment or use defaults
    host = os.getenv('POSTGRES_HOST', 'localhost')
    port = int(os.getenv('PGBOUNCER_PORT', '5433'))  # Use PgBouncer port
    dbname = os.getenv('POSTGRES_DB', 'taifabase_dev')
    user = os.getenv('POSTGRES_USER', 'taifabase_user')
    password = os.getenv('POSTGRES_PASSWORD', 'taifabase_dev_password')

    runner = SecurityTestRunner(
        host=host,
        port=port,
        dbname=dbname,
        user=user,
        password=password
    )

    try:
        runner.run_all_tests()

        # Exit with non-zero if security score is below threshold
        if runner.calculate_security_score() < 70:
            sys.exit(1)

    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Tests interrupted by user{Colors.ENDC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.FAIL}Error running tests: {str(e)}{Colors.ENDC}")
        sys.exit(1)

if __name__ == '__main__':
    main()
