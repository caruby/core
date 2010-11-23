package clinicaltrials.domain;

import clinicaltrials.domain.Study;

public class StudyEvent extends DomainObject
{
    /**
     * The offset from the beginning of the study.
     */
    private Double calendarEventPoint;

    /**
     * This event's study.
     * <p>
     * This property exercises a reference from a dependent to its owner.
     * </p>
     */
    private Study study;

    public StudyEvent()
    {
    }

    /**
     * @return the calendar event point
     */
    public Double getCalendarEventPoint()
    {
        return calendarEventPoint;
    }

    /**
     * @param calendarEventPoint the calendar event point to set
     */
    public void setCalendarEventPoint(Double calendarEventPoint)
    {
        this.calendarEventPoint = calendarEventPoint;
    }

    /**
     * @return the event study
     */
    public Study getStudy()
    {
        return study;
    }

    /**
     * @param study the event study to set
     */
    public void setStudy(Study study)
    {
        this.study = study;
    }
}
