class SolidQueue::ClaimedExecution < SolidQueue::Execution
  belongs_to :process

  class Result < Struct.new(:success, :error)
    def success?
      success
    end
  end

  CLAIM_ATTRIBUTES = %w[ job_id ]

  class << self
    def claiming(executions, &block)
      job_data = Array(executions).collect { |execution| execution.attributes.slice(*CLAIM_ATTRIBUTES) }

      insert_all(job_data)
      where(job_id: job_data.map { |data| data["job_id"]} ).tap do |claimed|
        block.call(claimed)
        SolidQueue.logger.info("[SolidQueue] Claimed #{claimed.size} jobs")
      end
    end

    def release_all
      includes(:job).each(&:release)
    end
  end

  def perform(process)
    claimed_by(process)

    result = execute
    if result.success?
      finished
    else
      failed_with(result.error)
    end
  end

  def release
    transaction do
      job.prepare_for_execution
      destroy!
    end
  end

  private
    def claimed_by(process)
      update!(process: process)
      SolidQueue.logger.info("[SolidQueue] Performing job #{job.id} - #{job.active_job_id}")
    end

    def execute
      ActiveJob::Base.execute(job.arguments)
      Result.new(true, nil)
    rescue Exception => e
      Result.new(false, e)
    end

    def finished
      transaction do
        job.finished
        destroy!
      end

      SolidQueue.logger.info("[SolidQueue] Performed job #{job.id} - #{job.active_job_id}")
    end

    def failed_with(error)
      transaction do
        job.failed_with(error)
        destroy!
      end

      SolidQueue.logger.info("[SolidQueue] Failed job #{job.id} - #{job.active_job_id}")
    end
end
