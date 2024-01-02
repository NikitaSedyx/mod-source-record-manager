package org.folio.services;

import io.vertx.core.Future;
import org.folio.dao.JournalRecordDao;
import org.folio.rest.jaxrs.model.JobExecutionSummaryDto;
import org.folio.rest.jaxrs.model.JournalRecord;
import org.folio.rest.jaxrs.model.JournalRecordCollection;
import org.folio.rest.jaxrs.model.RecordProcessingLogDto;
import org.folio.rest.jaxrs.model.RecordProcessingLogDtoCollection;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

/**
 * Implementation of the JournalRecordService.
 *
 * @see JournalRecordService
 */
@Service
public class JournalRecordServiceImpl implements JournalRecordService {

  @Autowired
  private JournalRecordDao journalRecordDao;

  @Override
  public Future<Boolean> deleteByJobExecutionId(String jobExecutionId, String tenantId) {
    return journalRecordDao.deleteByJobExecutionId(jobExecutionId, tenantId);
  }

  @Override
  public Future<JournalRecordCollection> getJobExecutionJournalRecords(String jobExecutionId, String sortBy, String order, String tenantId) {
    return journalRecordDao.getByJobExecutionId(jobExecutionId, sortBy, order, tenantId)
      .map(journalRecords -> new JournalRecordCollection()
        .withJournalRecords(journalRecords)
        .withTotalRecords(journalRecords.size()));
  }

  @Override
  public Future<RecordProcessingLogDtoCollection> getRecordProcessingLogDtoCollection(String jobExecutionId, String sortBy, String order, boolean errorsOnly, String entityType, int limit, int offset, String tenantId) {
    return journalRecordDao.getRecordProcessingLogDtoCollection(jobExecutionId, sortBy, order, errorsOnly, entityType, limit, offset, tenantId);
  }

  @Override
  public Future<RecordProcessingLogDto> getRecordProcessingLogDto(String jobExecutionId, String recordId, String tenantId) {
    return journalRecordDao.getRecordProcessingLogDto(jobExecutionId, recordId, tenantId);
  }

  @Override
  public Future<Optional<JobExecutionSummaryDto>> getJobExecutionSummaryDto(String jobExecutionId, String tenantId) {
    return journalRecordDao.getJobExecutionSummaryDto(jobExecutionId, tenantId);
  }

  @Override
  public Future<Integer> updateErrorJournalRecordsByOrderIdAndJobExecution(String jobExecutionId, String orderId, String error, String tenantId) {
    return journalRecordDao.updateErrorJournalRecordsByOrderIdAndJobExecution(jobExecutionId, orderId, error, tenantId);
  }

  @Override
  public void saveBatch(List<JournalRecord> journalRecords, String tenantId) {
    journalRecordDao.saveBatch(journalRecords, tenantId);
  }
}
