#!/usr/bin/env python3
"""
Test Data Generation Framework - Taifabase Phase 1
Author: Aisha Kamau - Senior QA Engineer
Date: 2025-10-03
Purpose: Scalable test data generation for RLS policy validation and performance testing

This framework provides comprehensive test data generation capabilities for
multi-tenant RLS testing, supporting various data volumes and complexity levels.
"""

import asyncio
import asyncpg
import json
import random
import uuid
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from faker import Faker

# Initialize Faker for realistic test data
fake = Faker()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class DataGenerationProfile:
    """Configuration profile for test data generation"""
    profile_name: str
    tenant_count: int
    records_per_tenant: int
    complexity_level: str  # 'simple', 'medium', 'complex'
    include_temporal_data: bool = True
    include_jsonb_metadata: bool = True
    include_relationships: bool = False
    data_distribution: str = 'uniform'  # 'uniform', 'skewed', 'realistic'

class TestDataGenerator:
    """Comprehensive test data generation framework"""
    
    def __init__(self, db_config: Dict[str, str]):
        self.db_config = db_config
        self.logger = logging.getLogger(self.__class__.__name__)
        
        # Predefined test tenant configurations
        self.test_tenants = {
            'alpha': {
                'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'name': 'Test Tenant Alpha',
                'slug': 'test-alpha',
                'industry': 'technology'
            },
            'beta': {
                'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                'name': 'Test Tenant Beta',
                'slug': 'test-beta',
                'industry': 'finance'
            },
            'gamma': {
                'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
                'name': 'Test Tenant Gamma',
                'slug': 'test-gamma',
                'industry': 'healthcare'
            },
            'delta': {
                'id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
                'name': 'Test Tenant Delta',
                'slug': 'test-delta',
                'industry': 'retail'
            },
            'epsilon': {
                'id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
                'name': 'Test Tenant Epsilon',
                'slug': 'test-epsilon',
                'industry': 'manufacturing'
            }
        }
        
        # Data generation profiles
        self.profiles = {
            'development': DataGenerationProfile(
                profile_name='development',
                tenant_count=3,
                records_per_tenant=100,
                complexity_level='simple'
            ),
            'testing': DataGenerationProfile(
                profile_name='testing',
                tenant_count=5,
                records_per_tenant=1000,
                complexity_level='medium'
            ),
            'performance': DataGenerationProfile(
                profile_name='performance',
                tenant_count=10,
                records_per_tenant=10000,
                complexity_level='complex'
            ),
            'stress': DataGenerationProfile(
                profile_name='stress',
                tenant_count=50,
                records_per_tenant=50000,
                complexity_level='complex',
                include_relationships=True
            )
        }
        
        # Categories and metadata patterns
        self.categories = [
            'finance', 'marketing', 'operations', 'technology', 
            'human_resources', 'sales', 'support', 'legal', 'general'
        ]
        
        self.metadata_patterns = {
            'simple': {
                'field_count': 3,
                'patterns': ['basic_info', 'status_tracking']
            },
            'medium': {
                'field_count': 6,
                'patterns': ['basic_info', 'status_tracking', 'performance_metrics', 'configuration']
            },
            'complex': {
                'field_count': 12,
                'patterns': ['basic_info', 'status_tracking', 'performance_metrics', 
                           'configuration', 'audit_trail', 'analytics', 'relationships']
            }
        }
    
    async def connect_db(self) -> asyncpg.Connection:
        """Establish database connection"""
        return await asyncpg.connect(**self.db_config)
    
    async def ensure_test_tenants(self, tenant_configs: List[Dict[str, str]]) -> bool:
        """Ensure test tenants exist in the database"""
        try:
            conn = await self.connect_db()
            
            for tenant_config in tenant_configs:
                # Insert or update tenant
                await conn.execute("""
                    INSERT INTO core.tenants (id, name, slug, status, created_at, updated_at)
                    VALUES ($1::UUID, $2, $3, 'active', NOW(), NOW())
                    ON CONFLICT (id) DO UPDATE SET
                        name = EXCLUDED.name,
                        slug = EXCLUDED.slug,
                        status = EXCLUDED.status,
                        updated_at = NOW()
                """, tenant_config['id'], tenant_config['name'], tenant_config['slug'])
                
                self.logger.info(f"Ensured tenant exists: {tenant_config['name']} ({tenant_config['slug']})")
            
            await conn.close()
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to ensure test tenants: {e}")
            return False
    
    def generate_metadata(self, complexity_level: str, tenant_info: Dict[str, str], record_index: int) -> Dict[str, Any]:
        """Generate JSONB metadata based on complexity level"""
        
        metadata_config = self.metadata_patterns[complexity_level]
        metadata = {}
        
        # Basic info pattern
        if 'basic_info' in metadata_config['patterns']:
            metadata.update({
                'record_type': 'test_data',
                'generation_timestamp': datetime.now().isoformat(),
                'tenant_industry': tenant_info.get('industry', 'unknown'),
                'record_index': record_index,
                'faker_seed': random.randint(1000, 9999)
            })
        
        # Status tracking pattern
        if 'status_tracking' in metadata_config['patterns']:
            statuses = ['active', 'inactive', 'pending', 'archived', 'processing']
            priorities = ['low', 'medium', 'high', 'critical']
            
            metadata.update({
                'status': random.choice(statuses),
                'priority': random.choice(priorities),
                'last_updated': fake.date_time_between(start_date='-30d', end_date='now').isoformat(),
                'version': random.randint(1, 10)
            })
        
        # Performance metrics pattern
        if 'performance_metrics' in metadata_config['patterns']:
            metadata.update({
                'performance_score': round(random.uniform(0.1, 100.0), 2),
                'usage_count': random.randint(1, 1000),
                'success_rate': round(random.uniform(0.7, 1.0), 3),
                'avg_response_time_ms': round(random.uniform(10, 500), 2)
            })
        
        # Configuration pattern
        if 'configuration' in metadata_config['patterns']:
            config_options = ['default', 'custom', 'advanced', 'minimal']
            feature_flags = ['feature_a', 'feature_b', 'feature_c', 'beta_features']
            
            metadata.update({
                'configuration_type': random.choice(config_options),
                'enabled_features': random.sample(feature_flags, random.randint(1, 3)),
                'settings': {
                    'auto_sync': random.choice([True, False]),
                    'notification_level': random.choice(['none', 'basic', 'detailed']),
                    'max_connections': random.randint(5, 100)
                }
            })
        
        # Audit trail pattern
        if 'audit_trail' in metadata_config['patterns']:
            metadata.update({
                'created_by_user': f"user_{random.randint(1, 100)}",
                'creation_method': random.choice(['api', 'ui', 'import', 'migration']),
                'modification_history': [
                    {
                        'timestamp': fake.date_time_between(start_date='-7d', end_date='now').isoformat(),
                        'action': random.choice(['create', 'update', 'view']),
                        'user_id': f"user_{random.randint(1, 50)}"
                    }
                    for _ in range(random.randint(1, 5))
                ]
            })
        
        # Analytics pattern
        if 'analytics' in metadata_config['patterns']:
            metadata.update({
                'analytics': {
                    'page_views': random.randint(1, 1000),
                    'unique_visitors': random.randint(1, 500),
                    'conversion_rate': round(random.uniform(0.01, 0.15), 4),
                    'bounce_rate': round(random.uniform(0.2, 0.8), 3),
                    'geographic_data': {
                        'country': fake.country(),
                        'city': fake.city(),
                        'timezone': fake.timezone()
                    }
                }
            })
        
        # Relationships pattern
        if 'relationships' in metadata_config['patterns']:
            metadata.update({
                'relationships': {
                    'parent_record_id': str(uuid.uuid4()) if random.random() > 0.7 else None,
                    'child_record_count': random.randint(0, 10),
                    'related_categories': random.sample(self.categories, random.randint(1, 3)),
                    'external_references': [
                        {
                            'type': random.choice(['api', 'file', 'url']),
                            'reference': fake.url() if random.choice([True, False]) else fake.file_name()
                        }
                        for _ in range(random.randint(0, 3))
                    ]
                }
            })
        
        return metadata
    
    def generate_temporal_data(self, base_date: datetime, distribution: str = 'uniform') -> datetime:
        """Generate temporal data with different distribution patterns"""
        
        if distribution == 'uniform':
            # Uniform distribution over last 90 days
            days_back = random.randint(0, 90)
            return base_date - timedelta(days=days_back)
        
        elif distribution == 'skewed':
            # 70% of data in last 30 days, 30% in previous 60 days
            if random.random() < 0.7:
                days_back = random.randint(0, 30)
            else:
                days_back = random.randint(31, 90)
            return base_date - timedelta(days=days_back)
        
        elif distribution == 'realistic':
            # Realistic business data pattern - more recent data
            # 50% last 7 days, 30% last 30 days, 20% older
            rand = random.random()
            if rand < 0.5:
                days_back = random.randint(0, 7)
            elif rand < 0.8:
                days_back = random.randint(8, 30)
            else:
                days_back = random.randint(31, 365)
            return base_date - timedelta(days=days_back)
        
        else:
            return base_date - timedelta(days=random.randint(0, 30))
    
    async def generate_sample_data_for_tenant(
        self, 
        tenant_config: Dict[str, str], 
        record_count: int, 
        profile: DataGenerationProfile
    ) -> int:
        """Generate sample data for a specific tenant"""
        
        conn = await self.connect_db()
        generated_count = 0
        
        try:
            tenant_id = tenant_config['id']
            tenant_name = tenant_config['name']
            
            self.logger.info(f"Generating {record_count} records for {tenant_name}...")
            
            # Generate records in batches for better performance
            batch_size = min(1000, record_count // 10 + 1)
            
            for batch_start in range(0, record_count, batch_size):
                batch_end = min(batch_start + batch_size, record_count)
                batch_records = []
                
                for i in range(batch_start, batch_end):
                    # Generate record data
                    record_name = f"{tenant_config.get('industry', 'Test')} Record {i+1}"
                    record_description = fake.text(max_nb_chars=200)
                    record_category = random.choice(self.categories)
                    
                    # Generate metadata based on complexity
                    metadata = self.generate_metadata(profile.complexity_level, tenant_config, i)
                    
                    # Generate temporal data
                    created_at = self.generate_temporal_data(
                        datetime.now(), 
                        profile.data_distribution
                    ) if profile.include_temporal_data else datetime.now()
                    
                    batch_records.append((
                        tenant_id,
                        record_name,
                        record_description,
                        record_category,
                        json.dumps(metadata),
                        tenant_id,  # created_by
                        created_at
                    ))
                
                # Insert batch
                await conn.executemany("""
                    INSERT INTO tenant.sample_data 
                    (tenant_id, name, description, category, metadata, created_by, created_at)
                    VALUES ($1::UUID, $2, $3, $4, $5::JSONB, $6::UUID, $7)
                """, batch_records)
                
                generated_count += len(batch_records)
                
                if generated_count % 1000 == 0:
                    self.logger.info(f"Generated {generated_count}/{record_count} records for {tenant_name}")
            
            self.logger.info(f"Completed generation for {tenant_name}: {generated_count} records")
            
        except Exception as e:
            self.logger.error(f"Failed to generate data for {tenant_config['name']}: {e}")
            raise
        
        finally:
            await conn.close()
        
        return generated_count
    
    async def cleanup_test_data(self, tenant_slugs: List[str] = None) -> int:
        """Clean up test data for specified tenants or all test tenants"""
        
        conn = await self.connect_db()
        deleted_count = 0
        
        try:
            if tenant_slugs:
                # Clean specific tenants
                for slug in tenant_slugs:
                    result = await conn.fetchval("""
                        DELETE FROM tenant.sample_data 
                        WHERE tenant_id IN (
                            SELECT id FROM core.tenants WHERE slug = $1
                        )
                    """, slug)
                    deleted_count += result or 0
                    self.logger.info(f"Cleaned up data for tenant slug: {slug}")
            else:
                # Clean all test data
                result = await conn.fetchval("""
                    DELETE FROM tenant.sample_data 
                    WHERE tenant_id IN (
                        SELECT id FROM core.tenants WHERE slug LIKE 'test-%'
                    )
                """)
                deleted_count = result or 0
                self.logger.info(f"Cleaned up all test data: {deleted_count} records")
        
        except Exception as e:
            self.logger.error(f"Failed to cleanup test data: {e}")
            raise
        
        finally:
            await conn.close()
        
        return deleted_count
    
    async def generate_data_by_profile(self, profile_name: str) -> Dict[str, Any]:
        """Generate test data according to a predefined profile"""
        
        if profile_name not in self.profiles:
            raise ValueError(f"Unknown profile: {profile_name}. Available: {list(self.profiles.keys())}")
        
        profile = self.profiles[profile_name]
        self.logger.info(f"Starting data generation with profile: {profile_name}")
        
        # Select tenants for this profile
        selected_tenants = list(self.test_tenants.values())[:profile.tenant_count]
        
        # Ensure tenants exist
        if not await self.ensure_test_tenants(selected_tenants):
            raise Exception("Failed to ensure test tenants exist")
        
        # Generate data for each tenant
        generation_results = {}
        total_records = 0
        start_time = datetime.now()
        
        for tenant_config in selected_tenants:
            records_generated = await self.generate_sample_data_for_tenant(
                tenant_config,
                profile.records_per_tenant,
                profile
            )
            
            generation_results[tenant_config['slug']] = {
                'tenant_name': tenant_config['name'],
                'records_generated': records_generated,
                'target_records': profile.records_per_tenant
            }
            
            total_records += records_generated
        
        end_time = datetime.now()
        generation_time = (end_time - start_time).total_seconds()
        
        # Generate summary report
        summary = {
            'profile_name': profile_name,
            'generation_timestamp': start_time.isoformat(),
            'generation_duration_seconds': generation_time,
            'total_tenants': len(selected_tenants),
            'total_records_generated': total_records,
            'target_records': profile.tenant_count * profile.records_per_tenant,
            'records_per_second': round(total_records / generation_time, 2) if generation_time > 0 else 0,
            'complexity_level': profile.complexity_level,
            'tenant_results': generation_results,
            'profile_config': {
                'tenant_count': profile.tenant_count,
                'records_per_tenant': profile.records_per_tenant,
                'complexity_level': profile.complexity_level,
                'include_temporal_data': profile.include_temporal_data,
                'include_jsonb_metadata': profile.include_jsonb_metadata,
                'data_distribution': profile.data_distribution
            }
        }
        
        self.logger.info(f"Data generation completed: {total_records} records in {generation_time:.2f}s")
        
        return summary
    
    async def validate_generated_data(self, tenant_slugs: List[str] = None) -> Dict[str, Any]:
        """Validate generated test data quality and consistency"""
        
        conn = await self.connect_db()
        validation_results = {}
        
        try:
            # Get data distribution by tenant
            tenant_data = await conn.fetch("""
                SELECT 
                    t.slug as tenant_slug,
                    t.name as tenant_name,
                    COUNT(sd.id) as record_count,
                    COUNT(DISTINCT sd.category) as unique_categories,
                    MIN(sd.created_at) as earliest_record,
                    MAX(sd.created_at) as latest_record,
                    AVG(LENGTH(sd.description)) as avg_description_length,
                    COUNT(CASE WHEN sd.metadata IS NOT NULL THEN 1 END) as records_with_metadata
                FROM core.tenants t
                LEFT JOIN tenant.sample_data sd ON t.id = sd.tenant_id
                WHERE t.slug LIKE 'test-%'
                GROUP BY t.slug, t.name
                ORDER BY t.slug
            """)
            
            total_records = 0
            
            for row in tenant_data:
                tenant_slug = row['tenant_slug']
                
                validation_results[tenant_slug] = {
                    'tenant_name': row['tenant_name'],
                    'record_count': row['record_count'],
                    'unique_categories': row['unique_categories'],
                    'earliest_record': row['earliest_record'].isoformat() if row['earliest_record'] else None,
                    'latest_record': row['latest_record'].isoformat() if row['latest_record'] else None,
                    'avg_description_length': float(row['avg_description_length']) if row['avg_description_length'] else 0,
                    'records_with_metadata': row['records_with_metadata'],
                    'metadata_coverage_percent': round(
                        (row['records_with_metadata'] / row['record_count'] * 100) if row['record_count'] > 0 else 0, 2
                    )
                }
                
                total_records += row['record_count']
            
            # Get category distribution
            category_distribution = await conn.fetch("""
                SELECT 
                    category,
                    COUNT(*) as record_count,
                    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
                FROM tenant.sample_data sd
                JOIN core.tenants t ON sd.tenant_id = t.id
                WHERE t.slug LIKE 'test-%'
                GROUP BY category
                ORDER BY record_count DESC
            """)
            
            # Get metadata pattern analysis
            metadata_analysis = await conn.fetchrow("""
                SELECT 
                    COUNT(CASE WHEN metadata ? 'record_type' THEN 1 END) as has_record_type,
                    COUNT(CASE WHEN metadata ? 'status' THEN 1 END) as has_status,
                    COUNT(CASE WHEN metadata ? 'performance_score' THEN 1 END) as has_performance_metrics,
                    COUNT(CASE WHEN metadata ? 'analytics' THEN 1 END) as has_analytics,
                    COUNT(*) as total_records
                FROM tenant.sample_data sd
                JOIN core.tenants t ON sd.tenant_id = t.id
                WHERE t.slug LIKE 'test-%' AND metadata IS NOT NULL
            """)
            
            validation_summary = {
                'validation_timestamp': datetime.now().isoformat(),
                'total_test_records': total_records,
                'tenant_count': len(validation_results),
                'category_distribution': [dict(row) for row in category_distribution],
                'metadata_patterns': dict(metadata_analysis) if metadata_analysis else {},
                'tenant_details': validation_results,
                'data_quality_score': self._calculate_data_quality_score(validation_results, metadata_analysis)
            }
            
        except Exception as e:
            self.logger.error(f"Data validation failed: {e}")
            raise
        
        finally:
            await conn.close()
        
        return validation_summary
    
    def _calculate_data_quality_score(self, tenant_results: Dict, metadata_analysis: Dict) -> float:
        """Calculate data quality score based on various metrics"""
        
        score = 0.0
        max_score = 100.0
        
        # Check record distribution balance (20 points)
        if tenant_results:
            record_counts = [t['record_count'] for t in tenant_results.values()]
            if record_counts:
                avg_records = sum(record_counts) / len(record_counts)
                variance = sum((count - avg_records) ** 2 for count in record_counts) / len(record_counts)
                balance_score = max(0, 20 - (variance / avg_records * 10)) if avg_records > 0 else 0
                score += balance_score
        
        # Check metadata coverage (30 points)
        if metadata_analysis and metadata_analysis['total_records'] > 0:
            coverage_metrics = [
                metadata_analysis['has_record_type'],
                metadata_analysis['has_status'],
                metadata_analysis['has_performance_metrics'],
                metadata_analysis['has_analytics']
            ]
            avg_coverage = sum(coverage_metrics) / (len(coverage_metrics) * metadata_analysis['total_records'])
            score += avg_coverage * 30
        
        # Check category diversity (20 points)
        if tenant_results:
            categories_per_tenant = [t['unique_categories'] for t in tenant_results.values()]
            if categories_per_tenant:
                avg_categories = sum(categories_per_tenant) / len(categories_per_tenant)
                category_score = min(20, avg_categories * 2.5)  # Max 8 categories for full score
                score += category_score
        
        # Check temporal distribution (15 points)
        if tenant_results:
            tenants_with_temporal = sum(1 for t in tenant_results.values() if t['earliest_record'] and t['latest_record'])
            temporal_score = (tenants_with_temporal / len(tenant_results)) * 15
            score += temporal_score
        
        # Check data completeness (15 points)
        if tenant_results:
            completeness_scores = []
            for tenant in tenant_results.values():
                tenant_completeness = (
                    (1 if tenant['record_count'] > 0 else 0) +
                    (1 if tenant['avg_description_length'] > 10 else 0) +
                    (1 if tenant['metadata_coverage_percent'] > 50 else 0)
                ) / 3
                completeness_scores.append(tenant_completeness)
            
            avg_completeness = sum(completeness_scores) / len(completeness_scores) if completeness_scores else 0
            score += avg_completeness * 15
        
        return round(min(score, max_score), 2)
    
    async def generate_performance_dataset(self, scale_factor: int = 1) -> Dict[str, Any]:
        """Generate large dataset for performance testing"""
        
        self.logger.info(f"Generating performance dataset with scale factor: {scale_factor}")
        
        # Create custom profile for performance testing
        perf_profile = DataGenerationProfile(
            profile_name=f'performance_scale_{scale_factor}',
            tenant_count=min(10 * scale_factor, 50),
            records_per_tenant=10000 * scale_factor,
            complexity_level='complex',
            include_temporal_data=True,
            include_jsonb_metadata=True,
            data_distribution='realistic'
        )
        
        # Use subset of tenants for performance testing
        selected_tenants = list(self.test_tenants.values())[:perf_profile.tenant_count]
        
        if not await self.ensure_test_tenants(selected_tenants):
            raise Exception("Failed to ensure test tenants exist")
        
        start_time = datetime.now()
        total_records = 0
        
        for tenant_config in selected_tenants:
            records_generated = await self.generate_sample_data_for_tenant(
                tenant_config,
                perf_profile.records_per_tenant,
                perf_profile
            )
            total_records += records_generated
        
        end_time = datetime.now()
        generation_time = (end_time - start_time).total_seconds()
        
        return {
            'scale_factor': scale_factor,
            'total_tenants': len(selected_tenants),
            'records_per_tenant': perf_profile.records_per_tenant,
            'total_records': total_records,
            'generation_time_seconds': generation_time,
            'records_per_second': round(total_records / generation_time, 2) if generation_time > 0 else 0,
            'complexity_level': perf_profile.complexity_level,
            'generation_timestamp': start_time.isoformat()
        }


async def main():
    """Main execution function for test data generation"""
    
    # Database configuration
    db_config = {
        'host': 'localhost',
        'port': 5433,
        'database': 'taifabase_dev',
        'user': 'postgres',
        'password': 'postgres'
    }
    
    generator = TestDataGenerator(db_config)
    
    print("=" * 80)
    print("Test Data Generation Framework - Taifabase Phase 1")
    print("Author: Aisha Kamau - Senior QA Engineer")
    print("=" * 80)
    
    try:
        # Generate data using testing profile
        print("\nGenerating test data using 'testing' profile...")
        generation_report = await generator.generate_data_by_profile('testing')
        
        print(f"\nGeneration Summary:")
        print(f"- Total Records: {generation_report['total_records_generated']}")
        print(f"- Generation Time: {generation_report['generation_duration_seconds']:.2f}s")
        print(f"- Records/Second: {generation_report['records_per_second']}")
        print(f"- Complexity Level: {generation_report['complexity_level']}")
        
        # Validate generated data
        print("\nValidating generated data quality...")
        validation_report = await generator.validate_generated_data()
        
        print(f"\nValidation Summary:")
        print(f"- Total Test Records: {validation_report['total_test_records']}")
        print(f"- Tenant Count: {validation_report['tenant_count']}")
        print(f"- Data Quality Score: {validation_report['data_quality_score']}/100")
        
        # Save reports
        import os
        os.makedirs('/home/bonnie/Projects/taifabase/database/testing/results', exist_ok=True)
        
        with open('/home/bonnie/Projects/taifabase/database/testing/results/data_generation_report.json', 'w') as f:
            json.dump(generation_report, f, indent=2)
        
        with open('/home/bonnie/Projects/taifabase/database/testing/results/data_validation_report.json', 'w') as f:
            json.dump(validation_report, f, indent=2)
        
        print(f"\nReports saved to testing/results/")
        print("- data_generation_report.json")
        print("- data_validation_report.json")
        
        print("\n" + "=" * 80)
        print("Test data generation completed successfully!")
        
    except Exception as e:
        logger.error(f"Data generation failed: {e}")
        print(f"\nERROR: Data generation failed: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    import sys
    result = asyncio.run(main())
    sys.exit(result)