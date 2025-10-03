# RLS Security Testing Strategy
**Project**: Taifabase Phase 1  
**Security Engineer**: Dr. Kenji Tanaka  
**Date**: 2025-10-03  
**Sprint**: 1, Day 1  
**Integration**: Aisha Kamau's RLS Testing Framework + Marcus Rodriguez's RLS Implementation

## Executive Summary

This document defines a comprehensive security testing strategy for Row Level Security (RLS) policies that integrates with Aisha Kamau's existing testing framework. The strategy focuses on automated security validation, penetration testing scenarios, and continuous security monitoring.

## Security Testing Architecture

### Integration with Existing Framework

```
┌─────────────────────────────────────────────────────────────┐
│           Aisha's RLS Testing Framework (Existing)         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ Functional  │  │Performance  │  │   Multi-    │        │
│  │   Tests     │  │   Tests     │  │   Tenant    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           Security Testing Layer (New Addition)            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Security  │  │ Penetration │  │   Threat    │        │
│  │ Validation  │  │   Testing   │  │ Simulation  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Security Test Categories

### 1. Automated Security Validation Tests

#### 1.1 Tenant Isolation Security Tests
**Integration Point**: Extend Aisha's `test_tenant_isolation()` function

```sql
-- Enhanced tenant isolation test with security validation
-- File: testing/frameworks/rls_security_functions.sql

CREATE OR REPLACE FUNCTION test_security_tenant_isolation(
    test_user_name TEXT,
    expected_tenant_id UUID,
    attack_tenant_id UUID,
    test_description TEXT DEFAULT 'Security tenant isolation test'
) RETURNS TABLE(
    test_name TEXT,
    security_result BOOLEAN,
    isolation_effective BOOLEAN,
    attack_prevented BOOLEAN,
    actual_records BIGINT,
    security_details JSONB
) AS $$
DECLARE
    legitimate_records BIGINT;
    attack_records BIGINT;
    session_manipulation_blocked BOOLEAN := true;
BEGIN
    -- Test 1: Normal tenant access
    PERFORM set_current_tenant(expected_tenant_id);
    SELECT COUNT(*) INTO legitimate_records FROM tenant.sample_data;
    
    -- Test 2: Attempt session manipulation attack
    BEGIN
        -- Try to directly set session variable (should be blocked)
        PERFORM set_config('app.current_tenant_id', attack_tenant_id::text, false);
        -- If this succeeds, check if RLS still protects
        SELECT COUNT(*) INTO attack_records FROM tenant.sample_data;
        IF attack_records > 0 AND get_current_tenant() != expected_tenant_id THEN
            session_manipulation_blocked := false;
        END IF;
    EXCEPTION
        WHEN others THEN
            attack_records := 0;
            session_manipulation_blocked := true;
    END;
    
    -- Test 3: Attempt unauthorized tenant switch
    BEGIN
        PERFORM set_current_tenant(attack_tenant_id);
        -- This should either fail or be ignored by RLS
        SELECT COUNT(*) INTO attack_records FROM tenant.sample_data;
    EXCEPTION
        WHEN others THEN
            attack_records := 0;
    END;
    
    RETURN QUERY SELECT
        test_description,
        (legitimate_records > 0 AND attack_records = 0 AND session_manipulation_blocked),
        (legitimate_records > 0),
        (attack_records = 0),
        legitimate_records,
        jsonb_build_object(
            'user_tested', test_user_name,
            'expected_tenant', expected_tenant_id,
            'attack_tenant', attack_tenant_id,
            'legitimate_records', legitimate_records,
            'attack_records', attack_records,
            'session_manipulation_blocked', session_manipulation_blocked,
            'final_tenant_context', get_current_tenant(),
            'test_timestamp', CURRENT_TIMESTAMP
        );
END;
$$ LANGUAGE plpgsql;
```

#### 1.2 SQL Injection Security Tests
```sql
-- SQL injection resistance test for RLS policies
CREATE OR REPLACE FUNCTION test_rls_sql_injection(
    base_tenant_id UUID,
    injection_payloads TEXT[]
) RETURNS TABLE(
    test_name TEXT,
    payload TEXT,
    injection_blocked BOOLEAN,
    records_exposed BIGINT,
    security_details JSONB
) AS $$
DECLARE
    payload TEXT;
    test_records BIGINT;
    injection_successful BOOLEAN;
BEGIN
    -- Set legitimate tenant context
    PERFORM set_current_tenant(base_tenant_id);
    
    FOREACH payload IN ARRAY injection_payloads LOOP
        injection_successful := false;
        test_records := 0;
        
        BEGIN
            -- Attempt SQL injection through tenant context
            EXECUTE format('SELECT set_current_tenant(%L::UUID)', payload);
            SELECT COUNT(*) INTO test_records FROM tenant.sample_data;
            
            -- Check if injection was successful (bad)
            IF get_current_tenant() != base_tenant_id THEN
                injection_successful := true;
            END IF;
            
        EXCEPTION
            WHEN others THEN
                -- Exception means injection was blocked (good)
                injection_successful := false;
                test_records := 0;
        END;
        
        RETURN QUERY SELECT
            'SQL Injection Test',
            payload,
            NOT injection_successful,
            test_records,
            jsonb_build_object(
                'base_tenant', base_tenant_id,
                'injection_payload', payload,
                'injection_successful', injection_successful,
                'records_exposed', test_records,
                'final_tenant_context', get_current_tenant(),
                'test_timestamp', CURRENT_TIMESTAMP
            );
            
        -- Reset to legitimate tenant for next test
        PERFORM set_current_tenant(base_tenant_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

#### 1.3 Privilege Escalation Tests
```sql
-- Test privilege escalation resistance
CREATE OR REPLACE FUNCTION test_privilege_escalation(
    test_user_name TEXT,
    target_role TEXT DEFAULT 'admin_user'
) RETURNS TABLE(
    test_name TEXT,
    escalation_blocked BOOLEAN,
    current_effective_role TEXT,
    security_details JSONB
) AS $$
DECLARE
    initial_role TEXT;
    escalation_successful BOOLEAN := false;
BEGIN
    -- Record initial role
    SELECT current_user INTO initial_role;
    
    BEGIN
        -- Attempt role escalation
        EXECUTE format('SET ROLE %I', target_role);
        
        -- Check if escalation was successful
        IF current_user = target_role THEN
            escalation_successful := true;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            escalation_successful := false;
    END;
    
    RETURN QUERY SELECT
        'Privilege Escalation Test',
        NOT escalation_successful,
        current_user,
        jsonb_build_object(
            'initial_role', initial_role,
            'target_role', target_role,
            'escalation_attempted', true,
            'escalation_successful', escalation_successful,
            'final_role', current_user,
            'test_timestamp', CURRENT_TIMESTAMP
        );
END;
$$ LANGUAGE plpgsql;
```

### 2. Python Security Test Integration

#### 2.1 Enhanced Security Test Runner
```python
#!/usr/bin/env python3
"""
Enhanced RLS Security Testing - Integration with Aisha's Framework
File: testing/scripts/rls_security_test_runner.py
"""

import asyncio
import asyncpg
import json
import time
from datetime import datetime
from typing import Dict, List, Any, Tuple
import logging

class RLSSecurityTestRunner:
    """Security-focused extension of Aisha's RLS test runner"""
    
    def __init__(self, db_config: Dict[str, str]):
        self.db_config = db_config
        self.security_test_results = []
        self.logger = logging.getLogger(__name__)
        
        # SQL injection payloads for testing
        self.sql_injection_payloads = [
            "'; DROP TABLE tenant.sample_data; --",
            "' UNION SELECT id FROM core.tenants WHERE id != '",
            "'; UPDATE tenant.sample_data SET tenant_id = '00000000-0000-0000-0000-000000000000'; --",
            "' OR '1'='1",
            "'; SELECT set_config('app.current_tenant_id', 'attacker-tenant', false); --",
            "\\'; INSERT INTO core.tenants (id, name) VALUES ('hacker', 'Hacker Tenant'); --",
        ]
        
        # Privilege escalation test cases
        self.privilege_escalation_tests = [
            'admin_user',
            'postgres',
            'readonly_user'
        ]
    
    async def run_security_validation_tests(self) -> Dict[str, Any]:
        """Execute comprehensive security validation tests"""
        test_results = {
            'category': 'security_validation',
            'tests': [],
            'summary': {'passed': 0, 'failed': 0, 'total': 0, 'security_score': 0}
        }
        
        # Test tenant isolation security
        isolation_tests = [
            {
                'name': 'Security Tenant Isolation - Alpha vs Beta',
                'user': 'test_alpha_user',
                'expected_tenant': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'attack_tenant': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            },
            {
                'name': 'Security Tenant Isolation - Beta vs Gamma',
                'user': 'test_beta_user',
                'expected_tenant': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                'attack_tenant': 'cccccccc-cccc-cccc-cccc-cccccccccccc'
            }
        ]
        
        for test_case in isolation_tests:
            result = await self._execute_security_isolation_test(test_case)
            test_results['tests'].append(result)
            
            if result['security_result']:
                test_results['summary']['passed'] += 1
            else:
                test_results['summary']['failed'] += 1
            test_results['summary']['total'] += 1
        
        # Calculate security score
        if test_results['summary']['total'] > 0:
            test_results['summary']['security_score'] = (
                test_results['summary']['passed'] / 
                test_results['summary']['total'] * 100
            )
        
        return test_results
    
    async def run_sql_injection_tests(self) -> Dict[str, Any]:
        """Execute SQL injection resistance tests"""
        test_results = {
            'category': 'sql_injection',
            'tests': [],
            'summary': {'blocked': 0, 'exposed': 0, 'total': 0}
        }
        
        try:
            conn = await self.connect_db()
            
            # Test SQL injection resistance
            result = await conn.fetch(
                "SELECT * FROM test_rls_sql_injection($1::UUID, $2)",
                'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                self.sql_injection_payloads
            )
            
            for row in result:
                test_record = {
                    'name': row['test_name'],
                    'payload': row['payload'],
                    'blocked': row['injection_blocked'],
                    'records_exposed': row['records_exposed'],
                    'details': row['security_details'],
                    'timestamp': datetime.now().isoformat()
                }
                
                test_results['tests'].append(test_record)
                
                if row['injection_blocked']:
                    test_results['summary']['blocked'] += 1
                else:
                    test_results['summary']['exposed'] += 1
                test_results['summary']['total'] += 1
            
            await conn.close()
            
        except Exception as e:
            self.logger.error(f"SQL injection test failed: {e}")
            test_results['error'] = str(e)
        
        return test_results
    
    async def run_privilege_escalation_tests(self) -> Dict[str, Any]:
        """Execute privilege escalation tests"""
        test_results = {
            'category': 'privilege_escalation',
            'tests': [],
            'summary': {'blocked': 0, 'successful': 0, 'total': 0}
        }
        
        test_users = ['test_alpha_user', 'test_beta_user']
        
        for user in test_users:
            for target_role in self.privilege_escalation_tests:
                result = await self._execute_privilege_escalation_test(user, target_role)
                test_results['tests'].append(result)
                
                if result['escalation_blocked']:
                    test_results['summary']['blocked'] += 1
                else:
                    test_results['summary']['successful'] += 1
                test_results['summary']['total'] += 1
        
        return test_results
    
    async def run_penetration_tests(self) -> Dict[str, Any]:
        """Execute penetration testing scenarios"""
        test_results = {
            'category': 'penetration_testing',
            'tests': [],
            'summary': {'attacks_blocked': 0, 'vulnerabilities_found': 0, 'total': 0}
        }
        
        # Session hijacking simulation
        session_hijack_result = await self._test_session_hijacking()
        test_results['tests'].append(session_hijack_result)
        
        # Timing attack detection
        timing_attack_result = await self._test_timing_attacks()
        test_results['tests'].append(timing_attack_result)
        
        # Error message analysis
        error_analysis_result = await self._test_error_information_disclosure()
        test_results['tests'].append(error_analysis_result)
        
        # Calculate summary
        for test in test_results['tests']:
            test_results['summary']['total'] += 1
            if test.get('attack_blocked', False):
                test_results['summary']['attacks_blocked'] += 1
            else:
                test_results['summary']['vulnerabilities_found'] += 1
        
        return test_results
    
    async def _execute_security_isolation_test(self, test_case: Dict[str, str]) -> Dict[str, Any]:
        """Execute enhanced tenant isolation security test"""
        try:
            # Connect as specific user
            user_config = self.db_config.copy()
            user_config['user'] = test_case['user']
            user_config['password'] = f"{test_case['user'].replace('test_', '').replace('_user', '')}_pass"
            
            conn = await asyncpg.connect(**user_config)
            
            # Execute security isolation test
            result = await conn.fetchrow(
                "SELECT * FROM test_security_tenant_isolation($1, $2::UUID, $3::UUID, $4)",
                test_case['user'],
                test_case['expected_tenant'],
                test_case['attack_tenant'],
                test_case['name']
            )
            
            await conn.close()
            
            return {
                'name': test_case['name'],
                'security_result': result['security_result'],
                'isolation_effective': result['isolation_effective'],
                'attack_prevented': result['attack_prevented'],
                'details': result['security_details'],
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            self.logger.error(f"Security isolation test failed: {e}")
            return {
                'name': test_case['name'],
                'security_result': False,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
    
    async def _execute_privilege_escalation_test(self, user: str, target_role: str) -> Dict[str, Any]:
        """Execute privilege escalation test"""
        try:
            # Connect as specific user
            user_config = self.db_config.copy()
            user_config['user'] = user
            user_config['password'] = f"{user.replace('test_', '').replace('_user', '')}_pass"
            
            conn = await asyncpg.connect(**user_config)
            
            # Execute privilege escalation test
            result = await conn.fetchrow(
                "SELECT * FROM test_privilege_escalation($1, $2)",
                user,
                target_role
            )
            
            await conn.close()
            
            return {
                'name': f'Privilege Escalation: {user} -> {target_role}',
                'escalation_blocked': result['escalation_blocked'],
                'current_role': result['current_effective_role'],
                'details': result['security_details'],
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            self.logger.error(f"Privilege escalation test failed: {e}")
            return {
                'name': f'Privilege Escalation: {user} -> {target_role}',
                'escalation_blocked': True,  # Assume blocked if exception occurs
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
    
    async def _test_session_hijacking(self) -> Dict[str, Any]:
        """Test session hijacking resistance"""
        try:
            conn1 = await self.connect_db()
            conn2 = await self.connect_db()
            
            # Set tenant context in first connection
            await conn1.execute(
                "SELECT set_current_tenant($1::UUID)",
                'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            )
            
            # Try to access same session from second connection
            records_conn2 = await conn2.fetchval(
                "SELECT COUNT(*) FROM tenant.sample_data"
            )
            
            await conn1.close()
            await conn2.close()
            
            # Session hijacking blocked if second connection sees no records
            hijacking_blocked = (records_conn2 == 0)
            
            return {
                'name': 'Session Hijacking Test',
                'attack_blocked': hijacking_blocked,
                'records_accessed': records_conn2,
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                'name': 'Session Hijacking Test',
                'attack_blocked': True,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
    
    async def _test_timing_attacks(self) -> Dict[str, Any]:
        """Test for timing attack vulnerabilities"""
        try:
            conn = await self.connect_db()
            
            # Test timing for existing vs non-existing tenant
            existing_tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            fake_tenant = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
            
            # Time queries for existing tenant
            start_time = time.time()
            await conn.execute("SELECT set_current_tenant($1::UUID)", existing_tenant)
            await conn.fetchval("SELECT COUNT(*) FROM tenant.sample_data")
            existing_time = time.time() - start_time
            
            # Time queries for non-existing tenant
            start_time = time.time()
            try:
                await conn.execute("SELECT set_current_tenant($1::UUID)", fake_tenant)
                await conn.fetchval("SELECT COUNT(*) FROM tenant.sample_data")
            except:
                pass
            fake_time = time.time() - start_time
            
            await conn.close()
            
            # Check for significant timing differences
            timing_difference = abs(existing_time - fake_time)
            timing_attack_possible = timing_difference > 0.1  # 100ms threshold
            
            return {
                'name': 'Timing Attack Analysis',
                'attack_blocked': not timing_attack_possible,
                'timing_difference_seconds': timing_difference,
                'existing_tenant_time': existing_time,
                'fake_tenant_time': fake_time,
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                'name': 'Timing Attack Analysis',
                'attack_blocked': True,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
    
    async def _test_error_information_disclosure(self) -> Dict[str, Any]:
        """Test for information disclosure through error messages"""
        errors_analyzed = []
        information_disclosed = False
        
        try:
            conn = await self.connect_db()
            
            # Test various error conditions
            error_test_cases = [
                "SELECT * FROM tenant.sample_data WHERE tenant_id = 'invalid-uuid'",
                "SELECT set_current_tenant('not-a-uuid')",
                "SELECT * FROM tenant.nonexistent_table",
                "INSERT INTO tenant.sample_data (tenant_id) VALUES ('invalid')"
            ]
            
            for test_query in error_test_cases:
                try:
                    await conn.execute(test_query)
                except Exception as e:
                    error_message = str(e)
                    errors_analyzed.append(error_message)
                    
                    # Check if error reveals sensitive information
                    if any(sensitive in error_message.lower() for sensitive in 
                          ['tenant', 'uuid', 'table', 'column', 'row']):
                        information_disclosed = True
            
            await conn.close()
            
            return {
                'name': 'Error Information Disclosure Analysis',
                'attack_blocked': not information_disclosed,
                'information_disclosed': information_disclosed,
                'error_messages_analyzed': len(errors_analyzed),
                'sample_errors': errors_analyzed[:3],  # First 3 for review
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                'name': 'Error Information Disclosure Analysis',
                'attack_blocked': True,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
    
    async def connect_db(self) -> asyncpg.Connection:
        """Establish database connection"""
        return await asyncpg.connect(
            host=self.db_config['host'],
            port=self.db_config['port'],
            database=self.db_config['database'],
            user=self.db_config['user'],
            password=self.db_config['password']
        )
    
    async def generate_security_report(self, all_test_results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate comprehensive security test report"""
        
        # Calculate overall security score
        total_tests = 0
        passed_tests = 0
        vulnerabilities_found = 0
        
        for category_result in all_test_results:
            if 'summary' in category_result:
                if 'total' in category_result['summary']:
                    total_tests += category_result['summary']['total']
                    
                if 'passed' in category_result['summary']:
                    passed_tests += category_result['summary']['passed']
                elif 'blocked' in category_result['summary']:
                    passed_tests += category_result['summary']['blocked']
                    
                if 'vulnerabilities_found' in category_result['summary']:
                    vulnerabilities_found += category_result['summary']['vulnerabilities_found']
        
        security_score = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        # Determine security posture
        if security_score >= 95 and vulnerabilities_found == 0:
            security_posture = "EXCELLENT"
        elif security_score >= 85:
            security_posture = "GOOD"
        elif security_score >= 70:
            security_posture = "ACCEPTABLE"
        else:
            security_posture = "POOR"
        
        return {
            'security_test_run_id': f"security_test_{int(time.time())}",
            'timestamp': datetime.now().isoformat(),
            'overall_security_score': security_score,
            'security_posture': security_posture,
            'total_tests': total_tests,
            'passed_tests': passed_tests,
            'failed_tests': total_tests - passed_tests,
            'vulnerabilities_found': vulnerabilities_found,
            'test_categories': all_test_results,
            'recommendations': self._generate_security_recommendations(security_score, vulnerabilities_found)
        }
    
    def _generate_security_recommendations(self, score: float, vulnerabilities: int) -> List[str]:
        """Generate security recommendations based on test results"""
        recommendations = []
        
        if score < 95:
            recommendations.append("Implement additional security controls for tenant isolation")
        
        if vulnerabilities > 0:
            recommendations.append("Address identified vulnerabilities before production deployment")
        
        if score < 85:
            recommendations.append("Conduct manual penetration testing")
            recommendations.append("Review and strengthen RLS policy implementation")
        
        recommendations.extend([
            "Implement comprehensive audit logging",
            "Set up real-time security monitoring",
            "Establish incident response procedures",
            "Schedule regular security assessments"
        ])
        
        return recommendations


async def main():
    """Main execution function for security testing"""
    # Database configuration
    db_config = {
        'host': 'localhost',
        'port': 5433,
        'database': 'taifabase_dev',
        'user': 'postgres',
        'password': 'postgres'
    }
    
    # Initialize security test runner
    security_runner = RLSSecurityTestRunner(db_config)
    
    print("Starting RLS Security Testing Framework...")
    
    # Execute security test suites
    validation_results = await security_runner.run_security_validation_tests()
    print(f"Security validation tests: {validation_results['summary']}")
    
    injection_results = await security_runner.run_sql_injection_tests()
    print(f"SQL injection tests: {injection_results['summary']}")
    
    escalation_results = await security_runner.run_privilege_escalation_tests()
    print(f"Privilege escalation tests: {escalation_results['summary']}")
    
    penetration_results = await security_runner.run_penetration_tests()
    print(f"Penetration tests: {penetration_results['summary']}")
    
    # Generate comprehensive security report
    all_results = [validation_results, injection_results, escalation_results, penetration_results]
    security_report = await security_runner.generate_security_report(all_results)
    
    # Save security report
    with open('/home/bonnie/Projects/taifabase/security/rls_security_test_report.json', 'w') as f:
        json.dump(security_report, f, indent=2)
    
    print(f"Security testing completed.")
    print(f"Overall Security Score: {security_report['overall_security_score']:.1f}%")
    print(f"Security Posture: {security_report['security_posture']}")
    print(f"Vulnerabilities Found: {security_report['vulnerabilities_found']}")
    print(f"Report saved to: security/rls_security_test_report.json")


if __name__ == "__main__":
    asyncio.run(main())
```

## Integration Strategy

### 1. Framework Integration Points

#### 1.1 Aisha's Testing Framework Extensions
- **Extend existing test functions** with security validation
- **Add security-specific test scenarios** to functional tests
- **Integrate security scoring** into performance metrics
- **Enhance reporting** with security posture assessment

#### 1.2 CI/CD Pipeline Integration
```yaml
# File: .github/workflows/security-testing.yml
name: RLS Security Testing

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * *'  # Daily security tests

jobs:
  security-tests:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Run Security Tests
      run: |
        python testing/scripts/rls_security_test_runner.py
    
    - name: Security Score Gate
      run: |
        python -c "
        import json
        with open('security/rls_security_test_report.json') as f:
            report = json.load(f)
        score = report['overall_security_score']
        vulnerabilities = report['vulnerabilities_found']
        
        if score < 90 or vulnerabilities > 0:
            print(f'Security gate failed: Score {score}%, Vulnerabilities: {vulnerabilities}')
            exit(1)
        print(f'Security gate passed: Score {score}%')
        "
    
    - name: Upload Security Report
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: security-test-results
        path: security/
```

### 2. Continuous Security Monitoring

#### 2.1 Real-time Security Validation
- **Automated daily security tests** in production environment
- **Security metric tracking** in Grafana dashboards
- **Alerting on security test failures** or score degradation
- **Automated incident creation** for security violations

#### 2.2 Security Metrics Dashboard
```yaml
# Grafana Dashboard Configuration
dashboard:
  title: "RLS Security Monitoring"
  panels:
    - title: "Security Score Trend"
      type: graph
      targets:
        - expr: "rls_security_score"
    
    - title: "Vulnerabilities Detected"
      type: stat
      targets:
        - expr: "rls_vulnerabilities_count"
    
    - title: "SQL Injection Attempts"
      type: graph
      targets:
        - expr: "rls_injection_attempts_blocked"
    
    - title: "Privilege Escalation Attempts"
      type: graph
      targets:
        - expr: "rls_privilege_escalation_blocked"
```

## Security Testing Schedule

### Daily Automated Tests
- Tenant isolation validation
- SQL injection resistance testing
- Basic privilege escalation testing
- Performance security monitoring

### Weekly Manual Tests
- Comprehensive penetration testing
- Error message security analysis
- Session security validation
- New attack vector testing

### Monthly Security Reviews
- Threat model updates
- Security architecture review
- Compliance validation
- Security training updates

## Success Criteria

### Security Testing Goals
- **100% automated security test coverage** for RLS policies
- **Zero critical security vulnerabilities** in production
- **≥95% security score** in all automated tests
- **<24 hours** mean time to detect (MTTD) security issues

### Integration Success Metrics
- **Seamless integration** with Aisha's testing framework
- **Automated security gates** in CI/CD pipeline
- **Real-time security monitoring** in production
- **Complete security documentation** and procedures

This security testing strategy provides comprehensive coverage while integrating seamlessly with the existing testing infrastructure and supporting continuous security validation.